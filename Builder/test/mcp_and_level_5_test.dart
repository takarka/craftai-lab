import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/features/mcp/domain/mcp_models.dart';
import 'package:builder/features/mcp/infrastructure/mcp_client.dart';
import 'package:builder/features/mcp/presentation/mcp_page.dart';
import 'package:builder/features/mcp/presentation/mcp_providers.dart';
import 'package:builder/features/tools/domain/tools_dispatcher.dart';
import 'package:builder/features/tools/infrastructure/notes_adapter.dart';
import 'package:builder/features/tools/infrastructure/persistent_tools_repository.dart';
import 'package:builder/features/tools/presentation/tools_providers.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late StorageDatabase storageDb;
  const testOwnerId = 'teacher_mcp_test';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mcp_test_');
    final dbPath = '${tempDir.path}/test_builder_mcp.db';
    storageDb = StorageDatabase(
      databasePath: dbPath,
      databaseFactory: databaseFactoryFfi,
    );
    await storageDb.open();

    final nowIso = DateTime.now().toUtc().toIso8601String();
    await storageDb.db.insert(StorageSchemaV1.tableWorkspaces, {
      'owner_id': testOwnerId,
      'installation_id': 'inst_mcp',
      'schema_version': 1,
      'workspace_epoch': 1,
      'created_at_utc': nowIso,
      'updated_at_utc': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  tearDown(() async {
    if (storageDb.isOpen) {
      await storageDb.close();
    }
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group(
    'F15-01, F15-02 & F15-10: Connectors Catalog, Disclosure & Coming Soon',
    () {
      test(
        'contains CraftAI catalog connector and 3 coming soon connectors',
        () {
          final connectors = McpConnector.allConnectors;
          expect(connectors.length, 4);

          // CraftAI Lessons
          final craftAi = connectors.firstWhere(
            (c) => c.id == McpConnector.craftAiLessonsId,
          );
          expect(craftAi.isComingSoon, isFalse);
          expect(craftAi.capabilities.length, 2);
          expect(
            craftAi.dataDisclosure,
            contains('Не передаёт персональные данные'),
          );

          // Google Drive (coming soon)
          final gDrive = connectors.firstWhere(
            (c) => c.id == McpConnector.googleDriveId,
          );
          expect(gDrive.isComingSoon, isTrue);

          // Google Calendar (coming soon)
          final gCal = connectors.firstWhere(
            (c) => c.id == McpConnector.googleCalendarId,
          );
          expect(gCal.isComingSoon, isTrue);

          // Kundelik (coming soon)
          final kundelik = connectors.firstWhere(
            (c) => c.id == McpConnector.kundelikId,
          );
          expect(kundelik.isComingSoon, isTrue);
        },
      );
    },
  );

  group('F15-03 & F15-04: Security Policy & Allowed Gateway Enforcement', () {
    test('allows official CraftAI gateway and localhost', () {
      final clientAllowed1 = McpClient(
        gatewayUrl: 'https://api.craftai.lab/mcp/v1',
        sessionTokenProvider: () => 'valid_token',
      );
      expect(clientAllowed1.gatewayUrl, 'https://api.craftai.lab/mcp/v1');

      final clientAllowed2 = McpClient(
        gatewayUrl: 'http://localhost:8080/mcp',
        sessionTokenProvider: () => 'valid_token',
      );
      expect(clientAllowed2.gatewayUrl, 'http://localhost:8080/mcp');
    });

    test('rejects arbitrary external URLs per security policy F15-04', () {
      expect(
        () => McpClient(
          gatewayUrl: 'https://arbitrary-malicious-site.com/mcp',
          sessionTokenProvider: () => 'valid_token',
        ),
        throwsA(
          isA<SecurityException>().having(
            (e) => e.message,
            'message',
            contains('запрещено политикой безопасности F15-04'),
          ),
        ),
      );
    });

    test('requires active session token for connection (F15-03)', () async {
      final clientNoToken = McpClient(sessionTokenProvider: () => null);

      expect(() => clientNoToken.connect(), throwsStateError);
    });
  });

  group(
    'F15-04, F15-05 & F15-06: Tools List, Search Lessons & Lesson Details',
    () {
      test(
        'connects, lists tools, searches catalog and retrieves full lesson detail',
        () async {
          final client = McpClient(
            sessionTokenProvider: () => 'auth_session_token_123',
          );

          // Connect
          final tools = await client.connect();
          expect(client.isConnected, isTrue);
          expect(tools.length, 2);
          expect(tools.any((t) => t.name == 'search_lessons'), isTrue);
          expect(tools.any((t) => t.name == 'get_lesson'), isTrue);

          // Search lessons by topic query
          final algebraHits = await client.searchLessons(query: 'Виета');
          expect(algebraHits.length, 1);
          expect(algebraHits.first.title, contains('Виета'));
          expect(algebraHits.first.subject, 'Алгебра');
          expect(algebraHits.first.grade, 8);

          // Search lessons by subject & grade
          final physicsHits = await client.searchLessons(
            query: '',
            subject: 'Физика',
            grade: 9,
          );
          expect(physicsHits.length, 1);
          expect(physicsHits.first.title, contains('Ньютона'));

          // Get lesson detail
          final detail = await client.getLesson('les_1');
          expect(detail, isNotNull);
          expect(detail!.title, contains('теорема Виета'));
          expect(detail.content, contains('План урока (40 минут)'));
          expect(detail.author, isNotEmpty);

          // Unknown lesson id returns null
          final unknown = await client.getLesson('non_existent_id');
          expect(unknown, isNull);
        },
      );
    },
  );

  group('F15-07: Sanitized Educational JSON-RPC 2.0 Logs', () {
    test(
      'logs MCP protocol calls and redacts sensitive authorization tokens',
      () async {
        final client = McpClient(
          sessionTokenProvider: () => 'sensitive_secret_jwt_token_456',
        );

        await client.connect();
        await client.searchLessons(query: 'геометрия');

        final logs = client.recentLogs;
        expect(logs, isNotEmpty);

        final latestLog = logs.first;
        expect(latestLog.method, contains('tools/call'));
        expect(latestLog.durationMs, greaterThan(0));

        // Verify secrets are redacted in request/response JSON
        for (final log in logs) {
          expect(
            log.requestJson,
            isNot(contains('sensitive_secret_jwt_token_456')),
          );
          expect(
            log.responseJson,
            isNot(contains('sensitive_secret_jwt_token_456')),
          );
        }
      },
    );
  });

  group('F15-08 & F15-09: Disconnect & Revoke Workflow', () {
    test(
      'disconnect immediately revokes access and invalidates subsequent calls',
      () async {
        final client = McpClient(sessionTokenProvider: () => 'valid_token');

        await client.connect();
        expect(client.isConnected, isTrue);

        await client.disconnect();
        expect(client.isConnected, isFalse);

        // Subsequent tool calls must throw StateError
        expect(() => client.listTools(), throwsStateError);
        expect(() => client.searchLessons(query: 'алгебра'), throwsStateError);
        expect(() => client.getLesson('les_1'), throwsStateError);
      },
    );
  });

  group('F15-06 & Integration: Saving MCP Lesson to Local Notes', () {
    test(
      'saves MCP lesson into assistant private workspace notes via confirmation',
      () async {
        final notesDir = Directory('${tempDir.path}/notes_mcp');
        final notesAdapter = NotesAdapter(rootDirectory: notesDir);
        final toolsRepo = PersistentToolsRepository(database: storageDb);
        await toolsRepo.ensureDefaultGrants(testOwnerId);
        final toolsDispatcher = ToolsDispatcher(
          repository: toolsRepo,
          notesAdapter: notesAdapter,
        );

        final client = McpClient(sessionTokenProvider: () => 'valid_token');
        await client.connect();
        final lesson = (await client.getLesson('les_1'))!;

        final container = ProviderContainer(
          overrides: [
            mcpClientProvider.overrideWithValue(client),
            toolsRepositoryProvider.overrideWithValue(toolsRepo),
            toolsDispatcherProvider.overrideWithValue(toolsDispatcher),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          mcpControllerProvider(testOwnerId).notifier,
        );
        final result = await notifier.saveLessonToNotes(lesson);

        expect(result.success, isTrue);

        // Verify note was stored through NotesAdapter in private area
        final storedNotes = await notesAdapter.listNotes(testOwnerId);
        expect(storedNotes.length, 1);
        expect(storedNotes.first.title, contains('теорема Виета'));
        expect(storedNotes.first.content, contains('План урока (40 минут)'));
      },
    );
  });

  group(
    'F15-V01 & S44: McpPage Widget Flow & 44x44 Touch Target Accessibility',
    () {
      testWidgets(
        'connects, searches lessons, opens detail, saves note, toggles logs and disconnects',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final toolsRepo = InMemoryToolsRepository();
          await toolsRepo.ensureDefaultGrants(testOwnerId);

          final client = McpClient(sessionTokenProvider: () => 'test_ui_token');

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                mcpClientProvider.overrideWithValue(client),
                toolsRepositoryProvider.overrideWithValue(toolsRepo),
              ],
              child: const MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: McpPage(ownerId: testOwnerId),
              ),
            ),
          );

          await tester.pumpAndSettle();

          // 1. Verify Page Title & Disclosure Banner (F15-02)
          expect(find.text('Внешние интеграции (MCP)'), findsOneWidget);
          expect(find.byKey(const Key('mcp.disclosureBanner')), findsOneWidget);
          expect(
            find.textContaining('Model Context Protocol (MCP)'),
            findsOneWidget,
          );

          // 2. Verify Connect Button & 44x44 Touch Target
          final connectBtn = find.byKey(const Key('mcp.connectBtn'));
          expect(connectBtn, findsOneWidget);
          final connectSize = tester.getSize(connectBtn);
          expect(connectSize.width, greaterThanOrEqualTo(44.0));
          expect(connectSize.height, greaterThanOrEqualTo(44.0));

          // 3. Connect to CraftAI Catalog
          await tester.tap(connectBtn);
          await tester.pumpAndSettle();

          // Verify connected state & capabilities listing (F15-02, F15-04)
          expect(find.text('Отключить каталог'), findsOneWidget);
          expect(find.textContaining('search_lessons'), findsOneWidget);
          expect(find.textContaining('get_lesson'), findsOneWidget);

          // 4. Search in Catalog
          final searchInput = find.byKey(const Key('mcp.searchInput'));
          expect(searchInput, findsOneWidget);
          await tester.enterText(searchInput, 'теорема');
          await tester.tap(find.byKey(const Key('mcp.searchSubmitBtn')));
          await tester.pumpAndSettle();

          expect(find.textContaining('теорема Виета'), findsOneWidget);

          // 5. Open Lesson Detail
          final openBtn = find.byKey(const Key('mcp.openLessonBtn.les_1'));
          expect(openBtn, findsOneWidget);
          await tester.tap(openBtn);
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('mcp.lessonDetailCard')), findsOneWidget);
          expect(find.textContaining('Цель урока'), findsOneWidget);

          // 6. Save lesson to notes (F15-06)
          final saveBtn = find.byKey(const Key('mcp.saveToNotesBtn'));
          expect(saveBtn, findsOneWidget);
          final saveSize = tester.getSize(saveBtn);
          expect(saveSize.width, greaterThanOrEqualTo(44.0));
          expect(saveSize.height, greaterThanOrEqualTo(44.0));

          await tester.tap(saveBtn);
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('mcp.savedNoteBanner')), findsOneWidget);

          // 7. Educational JSON-RPC Protocol Inspection ("Под капотом", F15-07)
          final toggleLogsBtn = find.byKey(const Key('mcp.toggleLogsBtn'));
          expect(toggleLogsBtn, findsOneWidget);
          await tester.ensureVisible(toggleLogsBtn);
          await tester.pumpAndSettle();
          await tester.tap(toggleLogsBtn);
          await tester.pumpAndSettle();

          expect(find.textContaining('JSON-RPC 2.0'), findsOneWidget);

          // 8. Disconnect connector (F15-08)
          final disconnectBtn = find.byKey(const Key('mcp.disconnectBtn'));
          expect(disconnectBtn, findsOneWidget);
          await tester.ensureVisible(disconnectBtn);
          await tester.pumpAndSettle();
          await tester.tap(disconnectBtn);
          await tester.pumpAndSettle();

          expect(find.text('Подключить каталог уроков'), findsOneWidget);
          expect(find.byKey(const Key('mcp.lessonDetailCard')), findsNothing);

          // 9. Done button returns to S43 (F15 acceptance criteria)
          final doneBtn = find.byKey(const Key('mcp.doneBtn'));
          expect(doneBtn, findsOneWidget);
          final doneSize = tester.getSize(doneBtn);
          expect(doneSize.width, greaterThanOrEqualTo(44.0));
          expect(doneSize.height, greaterThanOrEqualTo(44.0));
        },
      );
    },
  );
}
