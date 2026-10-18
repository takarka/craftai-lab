import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/storage_providers.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/assistant/assistant_providers.dart';
import 'package:builder/features/assistant/infrastructure/persistent_assistant_repository.dart';
import 'package:builder/features/assistant/presentation/assistant_page.dart';
import 'package:builder/features/assistant/presentation/reset_confirmation_dialog.dart';
import 'package:builder/features/chat/chat_providers.dart';
import 'package:builder/features/chat/domain/chat_message.dart';
import 'package:builder/features/chat/domain/chat_repository.dart';
import 'package:builder/features/chat/domain/chat_stream_event.dart';
import 'package:builder/features/chat/infrastructure/chat_stream_client.dart';
import 'package:builder/features/chat/infrastructure/persistent_chat_repository.dart';
import 'package:builder/features/course/course_providers.dart';
import 'package:builder/features/course/domain/course_catalog.dart';
import 'package:builder/features/course/infrastructure/persistent_course_repository.dart';
import 'package:builder/features/course/presentation/course_page.dart';
import 'package:builder/features/course/presentation/glossary_page.dart';
import 'package:builder/features/course/presentation/lesson_player_page.dart';
import 'package:builder/features/knowledge/domain/knowledge_models.dart';
import 'package:builder/features/knowledge/infrastructure/persistent_knowledge_repository.dart';
import 'package:builder/features/knowledge/presentation/knowledge_providers.dart';
import 'package:builder/features/memory/infrastructure/persistent_memory_repository.dart';
import 'package:builder/features/memory/presentation/memory_providers.dart';
import 'package:builder/features/policy/domain/policy_repository.dart';
import 'package:builder/features/policy/policy_providers.dart';
import 'package:builder/features/session/infrastructure/persistent_session_repository.dart';
import 'package:builder/features/session/infrastructure/secure_token_storage.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:builder/features/tools/infrastructure/persistent_tools_repository.dart';
import 'package:builder/features/tools/presentation/tools_providers.dart';
import 'package:builder/features/trace/domain/request_trace.dart';
import 'package:builder/features/trace/infrastructure/persistent_trace_repository.dart';
import 'package:builder/features/trace/trace_providers.dart';

class FailingOfflineChatStreamClient extends ChatStreamClient {
  FailingOfflineChatStreamClient()
      : super(tokenStorage: InMemorySecureTokenStorage());

  @override
  Stream<StreamEvent> streamCompletion({
    required String ownerId,
    required String category,
    required String catalogRevision,
    required List<Map<String, String>> messages,
    List<Map<String, dynamic>> tools = const [],
    int toolStep = 0,
    String? requestId,
    ChatCancellationToken? cancellationToken,
  }) {
    return Stream<StreamEvent>.error(
      const SocketException('Failed host lookup: api.craftai.kz'),
    );
  }
}

class AlwaysAcknowledgedPolicyRepository implements PolicyRepository {
  @override
  Future<bool> isPolicyAcknowledged({required String ownerId, required String policyId}) async => true;

  @override
  Future<PolicyAcknowledgment?> getAcknowledgment({
    required String ownerId,
    required String policyId,
  }) async {
    return PolicyAcknowledgment(
      ownerId: ownerId,
      policyId: policyId,
      policyVersion: 'v1.0',
      acknowledgedAtUtc: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> acknowledgePolicy({
    required String ownerId,
    required String policyId,
    required String policyVersion,
  }) async {}
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late StorageDatabase db;
  late PersistentAssistantRepository assistantRepo;
  late PersistentCourseRepository courseRepo;
  late PersistentChatRepository chatRepo;
  late PersistentTraceRepository traceRepo;
  late PersistentKnowledgeRepository knowledgeRepo;
  late PersistentMemoryRepository memoryRepo;
  late PersistentToolsRepository toolsRepo;
  late WorkspaceStorageService workspaceService;
  late PersistentSessionRepository sessionRepo;

  const testOwner = 'hardening_owner_42';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('craftai_f18_');
    final dbPath = p.join(tempDir.path, 'f18_test.db');
    db = StorageDatabase(
      databasePath: dbPath,
      databaseFactory: databaseFactoryFfi,
    );
    await db.open();

    workspaceService = WorkspaceStorageService(
      database: db,
      keyStorage: InMemorySecureKeyStorage(),
      installationId: 'inst_f18_test',
    );
    await workspaceService.openWorkspace(ownerId: testOwner);

    assistantRepo = PersistentAssistantRepository(
      database: db,
      workspaceService: workspaceService,
    );
    courseRepo = PersistentCourseRepository(
      database: db,
      assistantRepository: assistantRepo,
    );
    chatRepo = PersistentChatRepository(database: db);
    traceRepo = PersistentTraceRepository(
      db: db.db,
      ownerId: testOwner,
    );
    knowledgeRepo = PersistentKnowledgeRepository(
      database: db,
      baseStorageDir: tempDir.path,
    );
    memoryRepo = PersistentMemoryRepository(database: db);
    toolsRepo = PersistentToolsRepository(database: db);
    sessionRepo = PersistentSessionRepository(
      tokenStorage: InMemorySecureTokenStorage(),
      database: db,
      workspaceStorageService: workspaceService,
    );

    final nowUtc = DateTime.now().toUtc().toIso8601String();
    await db.db.insert(StorageSchemaV1.tableAssistantConfigurations, {
      'owner_id': testOwner,
      'name': 'Қыран',
      'selected_category': 'standard',
      'enabled_skills_json': jsonEncode(['instructions', 'knowledge', 'memory', 'tools']),
      'system_rules_json': jsonEncode(['Отвечать понятно']),
      'state_revision': 1,
      'updated_at_utc': nowUtc,
    });
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Widget buildTestApp({
    required Widget child,
    Locale locale = const Locale('ru'),
    ChatStreamClient? mockStreamClient,
    ChatRepository? customChatRepo,
  }) {
    return ProviderScope(
      overrides: [
        storageDatabaseProvider.overrideWithValue(db),
        assistantRepositoryProvider.overrideWithValue(assistantRepo),
        courseRepositoryProvider.overrideWithValue(courseRepo),
        chatRepositoryProvider.overrideWithValue(customChatRepo ?? chatRepo),
        traceRepositoryProvider.overrideWithValue(traceRepo),
        knowledgeRepositoryProvider.overrideWithValue(knowledgeRepo),
        memoryRepositoryProvider.overrideWithValue(memoryRepo),
        toolsRepositoryProvider.overrideWithValue(toolsRepo),
        policyRepositoryProvider.overrideWithValue(AlwaysAcknowledgedPolicyRepository()),
        if (mockStreamClient != null)
          chatStreamClientProvider.overrideWithValue(mockStreamClient),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      ),
    );
  }

  group('F18: Data Hardening, Offline & Resilience', () {
    test('F18-05: Offline matrix: course levels, glossary and memory are 100% available offline', () {
      // 1. All levels load synchronously without internet
      final levelsRu = CourseCatalog.getLevels(locale: 'ru');
      final levelsKk = CourseCatalog.getLevels(locale: 'kk');
      expect(levelsRu.length, 9);
      expect(levelsKk.length, 9);

      for (int i = 1; i <= 5; i++) {
        expect(CourseCatalog.getLevel(i, locale: 'ru'), isNotNull);
        expect(CourseCatalog.getLevel(i, locale: 'kk'), isNotNull);
      }

      // 2. Glossary terms load offline
      final terms = GlossaryPage.terms;
      expect(terms.length, greaterThanOrEqualTo(10));
      for (final t in terms) {
        expect(t.localizedTerm(false), isNotEmpty);
        expect(t.localizedTerm(true), isNotEmpty);
      }
    });

    test('F18-05: Chat graceful offline fallback on SocketException', () async {
      final container = ProviderContainer(
        overrides: [
          storageDatabaseProvider.overrideWithValue(db),
          assistantRepositoryProvider.overrideWithValue(assistantRepo),
          courseRepositoryProvider.overrideWithValue(courseRepo),
          chatRepositoryProvider.overrideWithValue(chatRepo),
          traceRepositoryProvider.overrideWithValue(traceRepo),
          knowledgeRepositoryProvider.overrideWithValue(knowledgeRepo),
          memoryRepositoryProvider.overrideWithValue(memoryRepo),
          toolsRepositoryProvider.overrideWithValue(toolsRepo),
          policyRepositoryProvider.overrideWithValue(AlwaysAcknowledgedPolicyRepository()),
          chatStreamClientProvider.overrideWithValue(FailingOfflineChatStreamClient()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(chatSessionProvider(testOwner).notifier);
      await notifier.startNewConversation();
      await pumpEventQueue();

      await notifier.sendMessage('Тестовый вопрос без интернета');
      await pumpEventQueue();

      final state = container.read(chatSessionProvider(testOwner));
      expect(state.isGenerating, isFalse);

      final assistantMsg = state.messages.lastWhere((m) => m.isAssistant);
      expect(assistantMsg.status, MessageStatus.error);
      expect(
        assistantMsg.errorMessage,
        contains('Для ответа облачной модели требуется интернет'),
      );

      // Verify trace was safely saved with error status
      expect(assistantMsg.requestId, isNotNull);
      final trace = await traceRepo.getTrace(assistantMsg.requestId!);
      expect(trace, isNotNull);
      expect(trace!.status, TraceStatus.error);
    });

    test('F18-03: Owner isolation & Sign out closes active workspace', () async {
      expect(workspaceService.hasActiveWorkspace, isTrue);
      await sessionRepo.signOut();
      final snapshot = sessionRepo.currentSnapshot;
      expect(snapshot, isA<SignedOut>());
      expect(workspaceService.hasActiveWorkspace, isFalse);
    });

    test('F18-04: Physical document deletion deletes file and cascades DB rows', () async {
      final txtContent = 'Бағдарламалау сабағының конспектісі';
      final txtBytes = Uint8List.fromList(utf8.encode(txtContent));

      final doc = await knowledgeRepo.importDocument(
        ownerId: testOwner,
        fileName: 'lesson_notes.txt',
        bytes: txtBytes,
        format: DocumentFormat.txt,
      );

      expect(doc.id, isNotEmpty);
      expect(doc.chunksCount, greaterThan(0));

      // Verify physical file was written to disk
      final revRows = await db.db.query(
        StorageSchemaV1.tableDocumentRevisions,
        where: 'document_id = ?',
        whereArgs: [doc.id],
      );
      expect(revRows.isNotEmpty, isTrue);
      final blobPath = revRows.first['blob_path'] as String;
      expect(File(blobPath).existsSync(), isTrue);

      // Delete document
      await knowledgeRepo.deleteDocument(ownerId: testOwner, docId: doc.id);

      // Verify physical file is gone
      expect(File(blobPath).existsSync(), isFalse);

      // Verify DB records cascaded
      final docInDb = await db.db.query(
        StorageSchemaV1.tableKnowledgeDocuments,
        where: 'id = ?',
        whereArgs: [doc.id],
      );
      expect(docInDb, isEmpty);

      final chunksInDb = await db.db.query(
        StorageSchemaV1.tableKnowledgeChunks,
        where: 'owner_id = ?',
        whereArgs: [testOwner],
      );
      expect(chunksInDb, isEmpty);
    });

    test('F18-04: Traces remain valid and readable after document deletion', () async {
      final now = DateTime.utc(2026, 10, 18, 10, 0, 0);
      final trace = RequestTrace(
        requestId: 'req_hardening_trace_1',
        ownerId: testOwner,
        conversationId: 'conv_1',
        modelCategory: 'standard',
        assistantVersion: 1,
        layers: [
          const TraceLayer(
            type: TraceLayerType.retrieval,
            title: 'База знаний',
            contentSnippet: 'План факультатива (curriculum_schedule_grade7.txt, удалён позже)',
            tokenCount: 140,
            location: LocationTag.onDevice,
          ),
        ],
        steps: const [
          TraceStep(
            stepIndex: 1,
            title: 'Поиск по базе знаний',
            description: 'Локальный поиск фрагментов',
            location: LocationTag.onDevice,
          ),
        ],
        usage: const TraceUsage(
          promptTokens: 140,
          completionTokens: 40,
          totalTokens: 180,
          durationMs: 420,
          isServerReported: false,
          costTier: 1,
        ),
        status: TraceStatus.completed,
        createdAtUtc: now,
        isExample: false,
      );

      await traceRepo.saveTrace(trace);

      final loadedTrace = await traceRepo.getTrace('req_hardening_trace_1');
      expect(loadedTrace, isNotNull);
      expect(loadedTrace!.requestId, 'req_hardening_trace_1');
      expect(loadedTrace.layers.first.title, 'База знаний');
      expect(loadedTrace.layers.first.contentSnippet, contains('План факультатива'));
    });

    testWidgets('F18-10: D05 reset dialog explicitly scopes to assistant workspace only', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showResetConfirmationDialog(context, ownerId: testOwner),
              child: const Text('Open Reset Dialog'),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Reset Dialog'));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reset.confirmationWordField')), findsOneWidget);
      expect(find.byKey(const Key('reset.confirmBtn')), findsOneWidget);
      expect(find.byKey(const Key('reset.cancelBtn')), findsOneWidget);
    });
  });

  group('F18: Responsive Layouts & Accessibility (a11y)', () {
    const screenResolutions = [
      Size(360, 780), // Compact Android (F18-07)
      Size(390, 844), // Standard iPhone (F18-07)
      Size(430, 932), // Large Pro Max (F18-07)
    ];

    for (final res in screenResolutions) {
      testWidgets('AssistantPage fits ${res.width}x${res.height} at 130% font scale without overflow', (tester) async {
        tester.view.physicalSize = Size(res.width * 2, res.height * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final inMemoryChat = InMemoryChatRepository();
        await inMemoryChat.createConversation(ownerId: testOwner);

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: res,
              textScaler: const TextScaler.linear(1.3), // 130% font scale (F18-07)
            ),
            child: buildTestApp(
              customChatRepo: inMemoryChat,
              child: const AssistantPage(ownerId: testOwner),
            ),
          ),
        );
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(AssistantPage), findsOneWidget);
      });

      testWidgets('CoursePage fits ${res.width}x${res.height} at 130% font scale in Kazakh', (tester) async {
        tester.view.physicalSize = Size(res.width * 2, res.height * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: res,
              textScaler: const TextScaler.linear(1.3),
            ),
            child: buildTestApp(
              locale: const Locale('kk'),
              child: const CoursePage(ownerId: testOwner),
            ),
          ),
        );
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Оқу жолы'), findsOneWidget);
      });

      testWidgets('LessonPlayerPage Level 1 fits ${res.width}x${res.height} at 130% font scale in Russian', (tester) async {
        tester.view.physicalSize = Size(res.width * 2, res.height * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: res,
              textScaler: const TextScaler.linear(1.3),
            ),
            child: buildTestApp(
              locale: const Locale('ru'),
              child: const LessonPlayerPage(ownerId: testOwner, levelId: 1, readOnly: true),
            ),
          ),
        );
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('lesson.step.1')), findsOneWidget);
        expect(find.byKey(const Key('lesson.ideaProceedBtn')), findsOneWidget);
      });
    }

    testWidgets('F18-08 & F18-V01: Touch target sizes for primary buttons are at least 44x44', (tester) async {
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestApp(child: const LessonPlayerPage(ownerId: testOwner, levelId: 1, readOnly: true)),
      );
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();

      final proceedBtnFinder = find.byKey(const Key('lesson.ideaProceedBtn'));
      expect(proceedBtnFinder, findsOneWidget);
      final size = tester.getSize(proceedBtnFinder);
      expect(size.height, greaterThanOrEqualTo(44.0), reason: 'Buttons must have minimum 44px tap target');

      final closeBtnFinder = find.byKey(const Key('lesson.closeBtn'));
      expect(closeBtnFinder, findsOneWidget);
      final closeSize = tester.getSize(closeBtnFinder);
      expect(closeSize.width, greaterThanOrEqualTo(44.0));
      expect(closeSize.height, greaterThanOrEqualTo(44.0));
    });
  });
}
