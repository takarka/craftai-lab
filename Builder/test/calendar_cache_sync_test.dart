import 'dart:convert';
import 'dart:io';

import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/calendar/application/calendar_sync_service.dart';
import 'package:builder/features/calendar/domain/calendar_models.dart';
import 'package:builder/features/calendar/infrastructure/builder_calendar_client.dart';
import 'package:builder/features/calendar/infrastructure/calendar_repository.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> eventJson(String id, {int version = 1, String title = 'Урок', bool weekly = true}) => {
  'id': id,
  'version': version,
  'title': title,
  'allDay': false,
  'start': '2026-10-19T09:00:00',
  'end': '2026-10-19T09:45:00',
  'timeZone': 'Asia/Almaty',
  'reminders': <int>[],
  if (weekly) 'recurrence': {'frequency': 'weekly', 'byWeekday': ['mon']},
};

CalendarChangesPage page(List<Map<String, dynamic>> items, String cursor, {bool more = false}) =>
    CalendarChangesPage.fromJson({'items': items, 'nextCursor': cursor, 'hasMore': more});

Map<String, dynamic> upsert(Map<String, dynamic> event) => {'type': 'upsert', 'eventId': event['id'], 'event': event};
Map<String, dynamic> tombstone(String id) => {'type': 'delete', 'eventId': id};

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late StorageDatabase storage;

  Future<void> workspace(String owner) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await storage.db.insert(StorageSchemaV1.tableWorkspaces, {
      'owner_id': owner,
      'installation_id': 'inst',
      'schema_version': 1,
      'workspace_epoch': 1,
      'created_at_utc': now,
      'updated_at_utc': now,
    });
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('calendar_cache_');
    storage = StorageDatabase(
      databasePath: '${tempDir.path}/cal.db',
      databaseFactory: databaseFactoryFfi,
    );
    await storage.open();
    await workspace('a');
    await workspace('b');
  });

  tearDown(() async {
    if (storage.isOpen) await storage.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('PersistentCalendarRepository', () {
    test('stores events, cursor and tombstones atomically per owner', () async {
      final repo = PersistentCalendarRepository(database: storage);
      await repo.applyChanges('a', page([upsert(eventJson('e1')), upsert(eventJson('e2'))], 'c1'), replaceAll: true);
      await repo.applyChanges('a', page([tombstone('e1'), upsert(eventJson('e2', version: 2, title: 'Новый'))], 'c2'), replaceAll: false);

      final events = await repo.events('a');
      expect(events.map((e) => e.id), ['e2']);
      expect(events.single.title, 'Новый');
      expect(events.single.recurrence!.byWeekday, [DateTime.monday]);
      expect(await repo.cursor('a'), 'c2');
      expect(await repo.syncedAt('a'), isNotNull);
    });

    test('owners are isolated', () async {
      final repo = PersistentCalendarRepository(database: storage);
      await repo.applyChanges('a', page([upsert(eventJson('e1'))], 'ca'), replaceAll: true);
      await repo.reconcileOverrides('a', const [OccurrenceOverride(eventId: 'e1', date: '2026-10-26', canceled: true)], const []);
      await repo.addPendingCreate('a', const PendingCalendarCreate(key: 'k', input: {'title': 'x'}, createdAtUtc: '2026-10-19T00:00:00Z'));

      expect(await repo.events('b'), isEmpty);
      expect(await repo.overrides('b'), isEmpty);
      expect(await repo.cursor('b'), isNull);
      expect(await repo.pendingCreates('b'), isEmpty);
    });

    test('a full download replaces the owner cache only', () async {
      final repo = PersistentCalendarRepository(database: storage);
      await repo.applyChanges('a', page([upsert(eventJson('old'))], 'c1'), replaceAll: true);
      await repo.applyChanges('b', page([upsert(eventJson('other'))], 'cb'), replaceAll: true);
      await repo.applyChanges('a', page([upsert(eventJson('new'))], 'c2'), replaceAll: true);
      expect((await repo.events('a')).map((e) => e.id), ['new']);
      expect((await repo.events('b')).map((e) => e.id), ['other']);
    });

    test('a tombstone also drops that event\'s overrides', () async {
      final repo = PersistentCalendarRepository(database: storage);
      await repo.applyChanges('a', page([upsert(eventJson('e1'))], 'c1'), replaceAll: true);
      await repo.reconcileOverrides('a', const [OccurrenceOverride(eventId: 'e1', date: '2026-10-26', canceled: true)], const []);
      await repo.applyChanges('a', page([tombstone('e1')], 'c2'), replaceAll: false);
      expect(await repo.overrides('a'), isEmpty);
    });

    test('purgeOwnerData removes the whole calendar cache of that owner', () async {
      final repo = PersistentCalendarRepository(database: storage);
      await repo.applyChanges('a', page([upsert(eventJson('e1'))], 'c1'), replaceAll: true);
      await repo.reconcileOverrides('a', const [OccurrenceOverride(eventId: 'e1', date: '2026-10-26', canceled: true)], const []);
      await repo.addPendingCreate('a', const PendingCalendarCreate(key: 'k', input: {'title': 'x'}, createdAtUtc: '2026-10-19T00:00:00Z'));
      await repo.applyChanges('b', page([upsert(eventJson('keep'))], 'cb'), replaceAll: true);

      await WorkspaceStorageService(
        database: storage,
        keyStorage: InMemorySecureKeyStorage(),
        installationId: 'inst',
      ).purgeOwnerData(ownerId: 'a');

      expect(await repo.events('a'), isEmpty);
      expect(await repo.overrides('a'), isEmpty);
      expect(await repo.pendingCreates('a'), isEmpty);
      expect(await repo.cursor('a'), isNull);
      expect((await repo.events('b')).map((e) => e.id), ['keep']);
    });
  });

  group('CalendarSyncService', () {
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    CalendarSyncService service(
      CalendarRepository repo,
      Future<http.Response> Function(http.Request) handler,
    ) => CalendarSyncService(
      client: BuilderCalendarClient(
        CraftAiClient(baseUri: Uri.parse('https://api.example.test'), httpClient: MockClient(handler)),
      ),
      repository: repo,
    );

    test('pages through changes by opaque cursor and applies tombstones', () async {
      final repo = InMemoryCalendarRepository();
      await repo.applyChanges('a', page([upsert(eventJson('gone'))], 'c0'), replaceAll: true);
      final cursors = <String?>[];
      await service(repo, (request) async {
        cursors.add(request.url.queryParameters['cursor']);
        return request.url.queryParameters['cursor'] == 'c0'
            ? json({'items': [upsert(eventJson('e1'))], 'nextCursor': 'c1+/=', 'hasMore': true})
            : json({'items': [tombstone('gone')], 'nextCursor': 'c2', 'hasMore': false});
      }).sync('a');

      expect(cursors, ['c0', 'c1+/=']);
      expect((await repo.events('a')).map((e) => e.id), ['e1']);
      expect(await repo.cursor('a'), 'c2');
    });

    test('first sync is a full download that replaces stale cache', () async {
      final repo = InMemoryCalendarRepository();
      await service(repo, (_) async => json({'items': [upsert(eventJson('e1'))], 'nextCursor': 'c1', 'hasMore': false})).sync('a');
      expect((await repo.events('a')).single.id, 'e1');
    });

    test('network failure leaves the cache and cursor untouched', () async {
      final repo = InMemoryCalendarRepository();
      await repo.applyChanges('a', page([upsert(eventJson('e1'))], 'c1'), replaceAll: true);
      await expectLater(service(repo, (_) async => http.Response('{}', 503)).sync('a'), throwsA(isA<CraftAiException>()));
      expect((await repo.events('a')).single.id, 'e1');
      expect(await repo.cursor('a'), 'c1');
    });

    test('an unknown create outcome is replayed with the same key, once accepted it is dropped', () async {
      final repo = InMemoryCalendarRepository();
      final keys = <String?>[];
      var fail = true;
      final svc = service(repo, (request) async {
        if (request.method == 'POST') {
          keys.add(request.headers['Idempotency-Key']);
          return fail ? http.Response('{}', 503) : json({}, 201);
        }
        return json({'items': <Object>[], 'nextCursor': 'c', 'hasMore': false});
      });

      expect(await svc.create('a', {'title': 'Урок'}, idempotencyKey: 'K1'), CalendarCreateOutcome.queued);
      expect(await repo.pendingCreates('a'), hasLength(1));
      fail = false;
      await svc.sync('a');

      expect(keys, ['K1', 'K1']);
      expect(await repo.pendingCreates('a'), isEmpty);
    });

    test('a definitive refusal removes the draft and is reported', () async {
      final repo = InMemoryCalendarRepository();
      await repo.addPendingCreate('a', const PendingCalendarCreate(key: 'K', input: {'title': 'Плохое'}, createdAtUtc: 'x'));
      final result = await service(repo, (request) async {
        if (request.method == 'POST') return http.Response('{}', 400);
        return json({'items': <Object>[], 'nextCursor': 'c', 'hasMore': false});
      }).sync('a');
      expect(result.rejected.single.input['title'], 'Плохое');
      expect(await repo.pendingCreates('a'), isEmpty);
    });

    test('refreshRange learns canceled and moved occurrences from the server', () async {
      final repo = InMemoryCalendarRepository();
      await repo.applyChanges('a', page([upsert(eventJson('e1'))], 'c'), replaceAll: true);
      await service(repo, (_) async => json({
        'from': '2026-10-19',
        'to': '2026-11-02',
        'items': [
          {'eventId': 'e1', 'occurrenceDate': '2026-10-19', 'title': 'Урок', 'allDay': false, 'start': '2026-10-19T09:00:00', 'end': '2026-10-19T09:45:00', 'isOverride': false},
          {'eventId': 'e1', 'occurrenceDate': '2026-11-02', 'title': 'Перенос', 'allDay': false, 'start': '2026-11-02T14:00:00', 'end': '2026-11-02T14:45:00', 'isOverride': true},
        ],
      })).refreshRange('a', '2026-10-19', '2026-11-02');

      final overrides = {for (final o in await repo.overrides('a')) o.date: o};
      expect(overrides['2026-10-26']!.canceled, isTrue);
      expect(overrides['2026-11-02']!.start, '2026-11-02T14:00:00');
      expect(overrides.containsKey('2026-10-19'), isFalse);
    });
  });
}
