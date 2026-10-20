import 'dart:convert';
import 'dart:io';

import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/features/calendar/application/calendar_reminder_service.dart';
import 'package:builder/features/calendar/domain/calendar_models.dart';
import 'package:builder/features/calendar/infrastructure/builder_calendar_client.dart';
import 'package:builder/features/calendar/infrastructure/calendar_repository.dart';
import 'package:builder/features/calendar/infrastructure/reminder_scheduler.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_reminder_scheduler.dart';

CalendarEvent lesson({List<int> reminders = const [15], CalendarRecurrence? recurrence}) => CalendarEvent(
  id: 'e1',
  title: 'Урок',
  allDay: false,
  start: '2026-10-20T09:00:00',
  end: '2026-10-20T09:45:00',
  timeZone: 'Asia/Almaty',
  reminders: reminders,
  recurrence: recurrence,
  version: 1,
);

Future<void> store(CalendarRepository repo, List<CalendarEvent> events) => repo.applyChanges(
  'a',
  CalendarChangesPage(
    items: [for (final e in events) CalendarChange(eventId: e.id, event: e)],
    nextCursor: 'c1',
    hasMore: false,
  ),
  replaceAll: true,
);

void main() {
  final now = DateTime.utc(2026, 10, 19, 6);
  late InMemoryCalendarRepository repo;
  late FakeScheduler scheduler;

  CalendarReminderService service([BuilderCalendarClient? client]) => CalendarReminderService(
    repository: repo,
    scheduler: scheduler,
    client: client,
    now: () => now,
  );

  setUp(() {
    repo = InMemoryCalendarRepository();
    scheduler = FakeScheduler();
  });

  test('reminders are off until the owner switches them on', () async {
    await store(repo, [lesson()]);
    final result = await service().sync('a');
    expect(result.status, ReminderStatus.off);
    expect(scheduler.replaced, isEmpty);
    expect(await service().isEnabled('a'), isFalse);
  });

  test('a refused permission keeps reminders off and schedules nothing', () async {
    await store(repo, [lesson()]);
    scheduler
      ..current = ReminderPermission.denied
      ..onRequest = ReminderPermission.denied;
    final permission = await service().enable('a');
    expect(permission, ReminderPermission.denied);
    expect(scheduler.requests, 1);
    expect(await service().isEnabled('a'), isFalse);
    expect(scheduler.replaced, isEmpty);
  });

  test('a granted permission switches reminders on and hands the plan to the system', () async {
    await store(repo, [lesson()]);
    scheduler
      ..current = ReminderPermission.denied
      ..onRequest = ReminderPermission.granted;
    expect(await service().enable('a'), ReminderPermission.granted);
    expect(await service().isEnabled('a'), isTrue);
    expect(scheduler.held.values.single.key, 'e1|2026-10-20|15');
    expect(scheduler.held.values.single.fireAtUtc, DateTime.utc(2026, 10, 20, 3, 45));
  });

  test('syncing again replaces the schedule and never doubles it', () async {
    await store(repo, [lesson(recurrence: const CalendarRecurrence(frequency: 'daily'))]);
    await service().enable('a');
    final first = {...scheduler.held.keys};
    await service().sync('a');
    await service().sync('a');
    expect(scheduler.held.keys.toSet(), first);
    expect(scheduler.held, hasLength(14));
    expect(scheduler.replaced.last.map((r) => r.notificationId).toSet(), hasLength(14));
  });

  test('editing the event moves its reminders; deleting it removes them', () async {
    await store(repo, [lesson(reminders: [15])]);
    await service().enable('a');
    await store(repo, [lesson(reminders: [60])]);
    await service().sync('a');
    expect(scheduler.held.values.single.key, 'e1|2026-10-20|60');
    await store(repo, const []);
    await service().sync('a');
    expect(scheduler.held, isEmpty);
  });

  test('revoking notifications in the system settings stops the plan and says so', () async {
    await store(repo, [lesson()]);
    await service().enable('a');
    scheduler.current = ReminderPermission.denied;
    final result = await service().sync('a');
    expect(result.status, ReminderStatus.permissionDenied);
    expect(scheduler.held, isEmpty);
    expect(await service().isEnabled('a'), isTrue, reason: 'the wish is kept, so allowing it again resumes reminders');

    scheduler.current = ReminderPermission.granted;
    expect((await service().sync('a')).status, ReminderStatus.scheduled);
    expect(scheduler.held, hasLength(1));
  });

  test('a platform without local notifications is reported, not faked', () async {
    await store(repo, [lesson()]);
    await repo.setRemindersEnabled('a', true);
    scheduler.current = ReminderPermission.unsupported;
    expect((await service().sync('a')).status, ReminderStatus.unsupported);
    expect(scheduler.replaced, isEmpty);
  });

  test('switching off removes the scheduled reminders', () async {
    await store(repo, [lesson()]);
    await service().enable('a');
    await service().disable('a');
    expect(scheduler.held, isEmpty);
    expect(await service().isEnabled('a'), isFalse);
    expect((await service().sync('a')).status, ReminderStatus.off);
  });

  test('clearing the device removes reminders without touching the setting', () async {
    await store(repo, [lesson()]);
    await service().enable('a');
    await service().clearDevice();
    expect(scheduler.held, isEmpty);
    expect(await service().isEnabled('a'), isTrue);
  });

  test('a system failure is reported as failed instead of promising delivery', () async {
    await store(repo, [lesson()]);
    await service().enable('a');
    scheduler.failReplace = true;
    expect((await service().sync('a')).status, ReminderStatus.failed);
  });

  group('with the server', () {
    Map<String, dynamic> eventJson() => lesson(recurrence: const CalendarRecurrence(frequency: 'daily')).toJson();

    BuilderCalendarClient client(http.Client http) => BuilderCalendarClient(
      CraftAiClient(baseUri: Uri.parse('https://api.example.test'), httpClient: http),
    );

    test('a date the server canceled is not reminded', () async {
      final api = MockClient((request) async {
        if (request.url.path.endsWith('/changes')) {
          return http.Response(
            jsonEncode({
              'items': [
                {'type': 'upsert', 'eventId': 'e1', 'event': eventJson()},
              ],
              'nextCursor': 'c1',
              'hasMore': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        // Occurrences: every day except 2026-10-21.
        final items = [
          for (var day = 19; day <= 31; day++)
            if (day != 21)
              {
                'eventId': 'e1',
                'occurrenceDate': '2026-10-$day',
                'title': 'Урок',
                'allDay': false,
                'start': '2026-10-${day}T09:00:00',
                'end': '2026-10-${day}T09:45:00',
                'timeZone': 'Asia/Almaty',
                'isOverride': false,
                'reminders': [15],
              },
        ];
        return http.Response(
          jsonEncode({'from': '2026-10-18', 'to': '2026-11-10', 'items': items}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await repo.setRemindersEnabled('a', true);
      final result = await service(client(api)).sync('a');
      expect(result.status, ReminderStatus.scheduled);
      expect(result.offline, isFalse);
      expect(scheduler.held.values.any((r) => r.key.contains('2026-10-21')), isFalse);
      expect(scheduler.held.values.any((r) => r.key.contains('2026-10-22')), isTrue);
    });

    test('with no connection the cached calendar is used and the screen can say so', () async {
      await store(repo, [lesson()]);
      await repo.setRemindersEnabled('a', true);
      final api = MockClient((_) async => throw const SocketException('down'));
      final result = await service(client(api)).sync('a');
      expect(result.status, ReminderStatus.scheduled);
      expect(result.offline, isTrue);
      expect(scheduler.held, hasLength(1));
    });

    test('without pulling the cache alone decides and the server is not asked', () async {
      await store(repo, [lesson()]);
      await repo.setRemindersEnabled('a', true);
      var calls = 0;
      final api = MockClient((_) async {
        calls++;
        return http.Response('{}', 500);
      });
      final result = await service(client(api)).sync('a', pullChanges: false, refreshWindow: false);
      expect(calls, 0);
      expect(result.offline, isFalse);
      expect(scheduler.held, hasLength(1));
    });
  });

  test('the setting is stored per owner and goes with the owner', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('reminder_setting_');
    final storage = StorageDatabase(
      databasePath: '${dir.path}/r.db',
      databaseFactory: databaseFactoryFfi,
    );
    try {
      await storage.open();
      final stamp = DateTime.now().toUtc().toIso8601String();
      for (final owner in ['a', 'b']) {
        await storage.db.insert(StorageSchemaV1.tableWorkspaces, {
          'owner_id': owner,
          'installation_id': 'inst',
          'schema_version': 1,
          'workspace_epoch': 1,
          'created_at_utc': stamp,
          'updated_at_utc': stamp,
        });
      }
      final persistent = PersistentCalendarRepository(database: storage);
      expect(await persistent.remindersEnabled('a'), isFalse);
      await persistent.setRemindersEnabled('a', true);
      expect(await persistent.remindersEnabled('a'), isTrue);
      expect(await persistent.remindersEnabled('b'), isFalse);
      await persistent.setRemindersEnabled('a', false);
      expect(await persistent.remindersEnabled('a'), isFalse);

      await persistent.setRemindersEnabled('b', true);
      await storage.db.delete(StorageSchemaV1.tableWorkspaces, where: 'owner_id = ?', whereArgs: ['b']);
      expect(await persistent.remindersEnabled('b'), isFalse, reason: 'cascade with the owner');
    } finally {
      if (storage.isOpen) await storage.close();
      await dir.delete(recursive: true);
    }
  });
}
