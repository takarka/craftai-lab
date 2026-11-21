import 'dart:convert';
import 'dart:io';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/features/agents/agents_providers.dart';
import 'package:builder/features/agents/domain/lab_agent.dart';
import 'package:builder/features/agents/infrastructure/agents_cache.dart';
import 'package:builder/features/agents/infrastructure/agents_repository.dart';
import 'package:builder/features/agents/infrastructure/lab_api_client.dart';
import 'package:builder/features/agents/presentation/agents_page.dart';
import 'package:builder/features/session/domain/auth_tokens.dart';
import 'package:builder/features/session/infrastructure/secure_token_storage.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> agentJson(String id, {int epoch = 0}) => {
  'id': id,
  'name': 'Агент $id',
  'epoch': epoch,
  'version': 1,
  'instruction': 'Инструкция $id',
  'task_type': 'prepare_tasks',
  'subject': 'Математика',
  'grade': '5',
};

class LabFixture {
  final tokens = InMemorySecureTokenStorage();
  final agents = <String, Map<String, dynamic>>{};
  final requests = <http.Request>[];
  bool offline = false;
  int _next = 0;
  late final client = MockClient((request) async {
    requests.add(request);
    if (offline) throw const SocketException('offline');
    final segments = request.url.pathSegments;
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (request.method == 'GET') {
      return response({'agents': agents.values.toList(), 'limit': 5});
    }
    if (request.method == 'POST' &&
        (segments.last == 'agents' || segments.last == 'copy')) {
      if (agents.length == 5) {
        return response({'code': 'agents.limit-reached'}, 409);
      }
      final id = 'new-${++_next}';
      final source = segments.last == 'copy'
          ? agents[segments[3]]!
          : <String, dynamic>{};
      final created = {...source, ...body, 'id': id, 'version': 1, 'epoch': 0};
      agents[id] = created;
      return response(created, 201);
    }
    final id = segments[3];
    if (request.method == 'PATCH') {
      agents[id] = {
        ...agents[id]!,
        ...body,
        'version': (agents[id]!['version'] as int) + 1,
      };
    } else if (request.method == 'DELETE') {
      agents.remove(id);
      return http.Response('', 204);
    } else if (segments.last == 'reset') {
      agents[id] = {...agents[id]!, 'epoch': (agents[id]!['epoch'] as int) + 1};
    }
    return response(agents[id]!);
  });
  http.Response response(Map<String, dynamic> body, [int status = 200]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
  Future<void> init() => tokens.writeSession(
    ownerId: 'alice',
    tokens: AuthTokens(
      accessToken: 'test-access',
      refreshToken: 'test-refresh',
      expiresAtUtc: DateTime.now().add(const Duration(hours: 1)),
    ),
  );
  LabApiClient get api => LabApiClient(
    baseUri: Uri.parse('https://lab.test'),
    client: client,
    tokens: tokens,
    ownerId: 'alice',
  );
  AgentsRepository repository([AgentsCache? cache]) =>
      AgentsRepository(api: api, cache: cache ?? MemoryAgentsCache());
}

Future<void> mountAgents(
  WidgetTester tester,
  AgentsRepository repository,
) async {
  final router = GoRouter(
    initialLocation: '/agents',
    routes: [
      GoRoute(
        path: '/agents',
        builder: (_, _) => const AgentsPage(ownerId: 'alice'),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, _) => const AgentEditorPage(ownerId: 'alice'),
          ),
          GoRoute(
            path: ':id',
            builder: (_, state) => AgentEditorPage(
              ownerId: 'alice',
              agentId: state.pathParameters['id'],
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentsRepositoryProvider('alice').overrideWithValue(repository),
        sessionProvider.overrideWith(
          (ref) => Stream.value(
            AuthenticatedSession(ownerId: 'alice', onboardingComplete: true),
          ),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test(
    'HTTP mutations use owner tokens, exact API paths and configuration-only copy',
    () async {
      final fixture = LabFixture();
      await fixture.init();
      fixture.agents['a'] = agentJson('a');
      final repo = fixture.repository();
      final first = (await repo.load()).agents.single;
      await repo.copy(first, 'Копия');
      final request = fixture.requests.last;
      expect(request.url.path, '/lab/v1/agents/a/copy');
      expect(request.headers['Authorization'], 'Bearer test-access');
      expect(jsonDecode(request.body), {'name': 'Копия'});
      await repo.update('a', {'name': 'Новое имя'});
      expect(fixture.requests.last.method, 'PATCH');
      expect(fixture.requests.last.url.path, '/lab/v1/agents/a');
      await fixture.tokens.clearSession();
      final count = fixture.requests.length;
      await expectLater(
        repo.load(),
        throwsA(
          isA<LabApiException>().having(
            (error) => error.code,
            'code',
            'session.changed',
          ),
        ),
      );
      expect(fixture.requests.length, count);
    },
  );

  test(
    '409 top-level error code is preserved; POST is never retried',
    () async {
      final fixture = LabFixture();
      await fixture.init();
      for (var i = 0; i < 5; i++) {
        fixture.agents['$i'] = agentJson('$i');
      }
      await expectLater(
        fixture.api.create({'name': 'Шестой'}),
        throwsA(
          isA<LabApiException>().having(
            (error) => error.code,
            'code',
            'agents.limit-reached',
          ),
        ),
      );
      expect(fixture.requests, hasLength(1));
    },
  );

  test(
    'v1 migration, encrypted cache restart, owner isolation and reset preserve course',
    () async {
      final dir = await Directory.systemTemp.createTemp('lab-agents-');
      final path = '${dir.path}/test.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            for (final sql in StorageSchemaV1.createStatements) {
              await db.execute(sql);
            }
          },
        ),
      );
      await legacy.close();
      final db = StorageDatabase(
        databasePath: path,
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      await db.open();
      expect(await db.db.getVersion(), 2);
      final columns = await db.db.rawQuery('PRAGMA table_info(messages)');
      expect(columns.any((row) => row['name'] == 'agent_id'), isTrue);
      final keys = InMemorySecureKeyStorage();
      SqliteAgentsCache cache(String owner) => SqliteAgentsCache(
        database: db,
        ownerId: owner,
        keys: keys,
        installationId: 'test',
      );
      final alice = cache('alice');
      final bob = cache('bob');
      await alice.replace([LabAgent(agentJson('a')), LabAgent(agentJson('b'))]);
      await bob.replace([LabAgent(agentJson('a'))]);
      await alice.select('b');
      await alice.saveDraft('a', 0, {'instruction': 'private text'});
      await alice.saveDraft('b', 0, {'instruction': 'second'});
      await bob.saveDraft('a', 0, {'instruction': 'bob'});
      final now = DateTime.now().toIso8601String();
      await db.db.insert('workspaces', {
        'owner_id': 'alice',
        'installation_id': 'test',
        'schema_version': 2,
        'workspace_epoch': 1,
        'created_at_utc': now,
        'updated_at_utc': now,
      });
      await db.db.insert('course_progress', {
        'owner_id': 'alice',
        'level_id': '1',
        'content_version': '0.2',
        'current_step': 3,
        'completed_checkpoints_json': '[]',
        'attempts_count': 1,
        'is_completed': 1,
        'updated_at_utc': now,
      });
      final progress = await db.db.query('course_progress');
      final raw = await db.db.query('lab_agents_cache');
      expect(raw.toString(), isNot(contains('Инструкция')));
      await db.close();
      await db.open();
      expect((await alice.read())!.map((agent) => agent.id), ['a', 'b']);
      expect(await alice.selected(), 'b');
      expect(await alice.readDraft('a', 0), {'instruction': 'private text'});
      await alice.replace([
        LabAgent(agentJson('a', epoch: 1)),
        LabAgent(agentJson('b')),
      ]);
      expect(await alice.readDraft('a', 0), isNull);
      expect(await alice.readDraft('b', 0), {'instruction': 'second'});
      expect(await bob.readDraft('a', 0), {'instruction': 'bob'});
      expect(await db.db.query('course_progress'), progress);
      await alice.replace([LabAgent(agentJson('b'))]);
      expect((await bob.read())!.single.id, 'a');
      expect(await db.db.query('course_progress'), progress);
    },
  );

  testWidgets(
    'two agents, configuration-only copy and scoped reset/delete dialogs',
    (tester) async {
      final fixture = LabFixture();
      await fixture.init();
      fixture.agents.addAll({'a': agentJson('a'), 'b': agentJson('b')});
      final cache = MemoryAgentsCache();
      await cache.saveDraft('a', 0, {'text': 'a'});
      await cache.saveDraft('b', 0, {'text': 'b'});
      await mountAgents(tester, fixture.repository(cache));
      expect(find.text('2 из 5'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('agent-menu-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Копировать'));
      await tester.pumpAndSettle();
      expect(find.text('3 из 5'), findsOneWidget);
      expect(find.text('Агент a — копия'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('agent-menu-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сбросить данные'));
      await tester.pumpAndSettle();
      expect(find.textContaining('прогресс курса сохранятся'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Сбросить данные'));
      await tester.pumpAndSettle();
      expect(fixture.agents['a']!['epoch'], 1);
      expect(fixture.agents['b']!['epoch'], 0);
      expect(await cache.readDraft('a', 0), isNull);
      expect(await cache.readDraft('b', 0), {'text': 'b'});
      await tester.tap(find.byKey(const ValueKey('agent-menu-b')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить агента'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Место в списке освободится'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(fixture.agents.containsKey('b'), isTrue);
    },
  );

  testWidgets('five agents disable creation and server copy limit is visible', (
    tester,
  ) async {
    final fixture = LabFixture();
    await fixture.init();
    for (var i = 0; i < 5; i++) {
      fixture.agents['$i'] = agentJson('$i');
    }
    await mountAgents(tester, fixture.repository());
    expect(find.text('5 из 5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Копировать'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Можно создать до 5 агентов'), findsWidgets);
    expect(fixture.agents, hasLength(5));
  });

  testWidgets('offline cache is marked and mutation buttons are disabled', (
    tester,
  ) async {
    final fixture = LabFixture();
    await fixture.init();
    fixture.agents['a'] = agentJson('a');
    final repo = fixture.repository();
    await repo.load();
    fixture.offline = true;
    await mountAgents(tester, repo);
    expect(find.textContaining('Показана сохранённая копия'), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuButton<String>>(
            find.byKey(const ValueKey('agent-menu-a')),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets(
    'creates agents with only name and instruction and persists draft',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = LabFixture();
      await fixture.init();
      final repo = fixture.repository();
      await mountAgents(tester, repo);
      for (var i = 1; i <= 2; i++) {
        await tester.tap(find.text('Создать агента'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('agent-name')),
          'Учитель $i',
        );
        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(find.byType(ChoiceChip), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('agent-instruction')),
          'Редактируемая инструкция $i',
        );
        await tester.pumpAndSettle();
        expect(
          (await repo.cache.readDraft('__new__', 0))!['instruction'],
          'Редактируемая инструкция $i',
        );
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Создать агента'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Создать агента'));
        await tester.pumpAndSettle();
        expect(find.text('$i из 5'), findsOneWidget);
        final request = fixture.requests.lastWhere(
          (request) => request.method == 'POST',
        );
        expect(jsonDecode(request.body), {
          'name': 'Учитель $i',
          'instruction': 'Редактируемая инструкция $i',
        });
        expect(await repo.cache.readDraft('__new__', 0), isNull);
      }
      expect(fixture.agents.values.map((agent) => agent['instruction']), [
        'Редактируемая инструкция 1',
        'Редактируемая инструкция 2',
      ]);
    },
  );

  testWidgets('name and instruction are required before creating an agent', (
    tester,
  ) async {
    final fixture = LabFixture();
    await fixture.init();
    await mountAgents(tester, fixture.repository());
    await tester.tap(find.text('Создать агента'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Создать агента'));
    await tester.pumpAndSettle();
    expect(find.text('Заполните поле'), findsNWidgets(2));
    expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('restores a legacy draft directly into the simplified form', (
    tester,
  ) async {
    final fixture = LabFixture();
    await fixture.init();
    final cache = MemoryAgentsCache();
    await cache.saveDraft('__new__', 0, {
      'name': 'Помощник',
      'instruction': 'Объясняй понятным языком',
      'subject': 'Физика',
      'grade': '8',
      'requirements': 'Три задания',
      'wizard': true,
      'preview': false,
      'version': 0,
    });
    await mountAgents(tester, fixture.repository(cache));
    await tester.tap(find.text('Создать агента'));
    await tester.pumpAndSettle();
    expect(find.text('Помощник'), findsOneWidget);
    expect(find.text('Объясняй понятным языком'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.tap(find.widgetWithText(FilledButton, 'Создать агента'));
    await tester.pumpAndSettle();
    expect(
      fixture.agents.values.single['instruction'],
      'Объясняй понятным языком',
    );
  });
}
