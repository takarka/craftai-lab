import 'dart:io';
import 'package:builder/app/providers.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/storage_providers.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/features/assistant/presentation/assistant_page.dart';
import 'package:builder/features/chat/chat_providers.dart';
import 'package:builder/features/chat/domain/chat_message.dart';
import 'package:builder/features/chat/domain/conversation.dart';
import 'package:builder/features/chat/infrastructure/persistent_chat_repository.dart';
import 'package:builder/features/policy/domain/policy_repository.dart';
import 'package:builder/features/policy/policy_providers.dart';
import 'package:builder/features/trace/domain/request_trace.dart';
import 'package:builder/features/trace/domain/trace_analogy.dart';
import 'package:builder/features/trace/infrastructure/persistent_trace_repository.dart';
import 'package:builder/features/trace/presentation/trace_sheet.dart';
import 'package:builder/features/trace/trace_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockPolicyRepository implements PolicyRepository {
  bool acknowledged = true;

  @override
  Future<bool> isPolicyAcknowledged({required String ownerId, required String policyId}) async {
    return acknowledged;
  }

  @override
  Future<PolicyAcknowledgment?> getAcknowledgment({required String ownerId, required String policyId}) async {
    return acknowledged
        ? PolicyAcknowledgment(
            ownerId: ownerId,
            policyId: policyId,
            policyVersion: 'v1.0',
            acknowledgedAtUtc: DateTime.now().toUtc(),
          )
        : null;
  }

  @override
  Future<void> acknowledgePolicy({
    required String ownerId,
    required String policyId,
    required String policyVersion,
  }) async {
    acknowledged = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late Database testDb;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('f08_test_');
    dbPath = p.join(tempDir.path, 'builder_test.db');
    testDb = await openDatabase(
      dbPath,
      version: StorageSchemaV1.version,
      onCreate: (db, version) async {
        for (final statement in StorageSchemaV1.createStatements) {
          await db.execute(statement);
        }
      },
    );

    // Insert mock workspace
    await testDb.insert(StorageSchemaV1.tableWorkspaces, {
      'owner_id': 'owner_f08',
      'installation_id': 'inst_f08',
      'schema_version': 1,
      'workspace_epoch': 1,
      'created_at_utc': DateTime.now().toUtc().toIso8601String(),
      'updated_at_utc': DateTime.now().toUtc().toIso8601String(),
    });
  });

  tearDown(() async {
    await testDb.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('F08 Execution Trace Domain & Serialization', () {
    test('trace provider saves traces under the authenticated workspace owner', () async {
      await testDb.execute('PRAGMA foreign_keys = ON');
      final storage = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await storage.open();
      final container = ProviderContainer(overrides: [
        storageDatabaseProvider.overrideWithValue(storage),
        sessionProvider.overrideWithValue(AsyncData(
          AuthenticatedSession(ownerId: 'owner_f08', onboardingComplete: true),
        )),
      ]);
      addTearDown(container.dispose);
      final repository = container.read(traceRepositoryProvider);
      expect((repository as PersistentTraceRepository).ownerId, 'owner_f08');
      final trace = RequestTrace.fromJson({
        ...PersistentTraceRepository.createSampleFixture().toJson(),
        'ownerId': 'owner_f08',
      });
      await repository.saveTrace(trace);
      expect(await repository.getTrace(trace.requestId), isNotNull);
    });

    test('RequestTrace serializes and deserializes accurately', () {
      final now = DateTime.utc(2026, 10, 17, 12, 0, 0);
      final trace = RequestTrace(
        requestId: 'req_123',
        ownerId: 'owner_f08',
        conversationId: 'conv_1',
        modelCategory: 'standard',
        assistantVersion: 2,
        layers: [
          const TraceLayer(
            type: TraceLayerType.instruction,
            title: '1 · Инструкция v2',
            contentSnippet: 'Отвечай кратко.',
            tokenCount: 45,
            location: LocationTag.onDevice,
          ),
          const TraceLayer(
            type: TraceLayerType.response,
            title: 'Текст ответа',
            contentSnippet: 'Ответ модели',
            tokenCount: 30,
            location: LocationTag.abroad,
          ),
        ],
        steps: [
          const TraceStep(
            stepIndex: 1,
            title: 'Вы написали',
            description: 'Вопрос',
            location: LocationTag.onDevice,
          ),
          const TraceStep(
            stepIndex: 4,
            title: 'Модель «standard»',
            description: 'Генерация',
            location: LocationTag.abroad,
            durationMs: 1200,
          ),
        ],
        usage: const TraceUsage(
          promptTokens: 45,
          completionTokens: 30,
          totalTokens: 75,
          durationMs: 1200,
          isServerReported: true,
          costTier: 2,
        ),
        status: TraceStatus.completed,
        createdAtUtc: now,
        isExample: false,
      );

      final json = trace.toJson();
      final restored = RequestTrace.fromJson(json);

      expect(restored.requestId, 'req_123');
      expect(restored.layers.length, 2);
      expect(restored.layers[0].title, '1 · Инструкция v2');
      expect(restored.steps.length, 2);
      expect(restored.usage.totalTokens, 75);
      expect(restored.usage.isServerReported, isTrue);
      expect(restored.status, TraceStatus.completed);
      expect(restored.isExample, isFalse);
    });

    test('RequestTrace.fromExecution constructs 5 steps and layers correctly', () {
      final trace = RequestTrace.fromExecution(
        requestId: 'req_exec_1',
        ownerId: 'owner_f08',
        conversationId: 'conv_1',
        modelCategory: 'fast',
        assistantVersion: 1,
        userPrompt: 'Посчитай 2 + 2',
        responseText: '2 + 2 = 4',
        durationMs: 850,
        status: TraceStatus.completed,
        serverPromptTokens: 120,
        serverCompletionTokens: 15,
        costTier: 1,
      );

      expect(trace.steps.length, 5);
      expect(trace.steps[0].title, 'Вы написали');
      expect(trace.steps[1].title, 'Приложение собрало запрос');
      expect(trace.steps[2].title, 'Сервер CraftAI');
      expect(trace.steps[3].title, 'Модель «fast»');
      expect(trace.steps[4].title, 'Ответ на телефоне');

      expect(trace.usage.promptTokens, 120);
      expect(trace.usage.completionTokens, 15);
      expect(trace.usage.totalTokens, 135);
      expect(trace.usage.isServerReported, isTrue);
      expect(trace.usage.costTier, 1);
    });

    test('TraceAnalogy provides accurate content in RU and KK', () {
      final ru = TraceAnalogy.getForLanguage('ru');
      expect(ru.title, 'Секретарь и эксперт');
      expect(ru.items.length, 5);
      expect(ru.items.first.lifeTerm, 'Секретарь');
      expect(ru.items.first.assistantTerm, 'Приложение');

      final kk = TraceAnalogy.getForLanguage('kk');
      expect(kk.title, 'Хатшы және сарапшы');
      expect(kk.items.length, 5);
      expect(kk.items.first.lifeTerm, 'Хатшы');
      expect(kk.items.first.assistantTerm, 'Қосымша');
    });
  });

  group('F08 Trace Repository & SQLite Persistence', () {
    test('PersistentTraceRepository saves and reads trace in SQLite', () async {
      final repo = PersistentTraceRepository(db: testDb, ownerId: 'owner_f08');

      final trace = RequestTrace.fromExecution(
        requestId: 'req_sqlite_1',
        ownerId: 'owner_f08',
        conversationId: 'conv_sqlite',
        modelCategory: 'standard',
        assistantVersion: 1,
        userPrompt: 'Тест сохранения',
        responseText: 'Успешно сохранено',
        durationMs: 1400,
        status: TraceStatus.completed,
      );

      await repo.saveTrace(trace);

      final loaded = await repo.getTrace('req_sqlite_1');
      expect(loaded, isNotNull);
      expect(loaded!.requestId, 'req_sqlite_1');
      expect(loaded.modelCategory, 'standard');
      expect(loaded.steps.length, 5);

      final nonExistent = await repo.getTrace('does_not_exist');
      expect(nonExistent, isNull);
    });

    test('getSampleTrace returns fixture clearly marked as example', () async {
      final repo = PersistentTraceRepository(db: testDb, ownerId: 'owner_f08');
      final sample = await repo.getSampleTrace();

      expect(sample.isExample, isTrue);
      expect(sample.usage.totalTokens, 748);
      expect(sample.usage.durationMs, 4600);
      expect(sample.steps.length, 5);
    });
  });

  group('F08 S31 TraceSheet Presentation Widgets', () {
    testWidgets('renders S31 Schema tab with 5 steps, location chips, and metrics', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final traceRepo = InMemoryTraceRepository();
      final sample = PersistentTraceRepository.createSampleFixture();
      await traceRepo.saveTrace(sample);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            traceRepositoryProvider.overrideWithValue(traceRepo),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: TraceSheet(requestId: 'sample-trace-748'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('Под капотом'), findsOneWidget);
      expect(find.text('Данные за рубежом'), findsOneWidget);
      expect(find.text('Пример'), findsOneWidget);

      // Verify 3 tabs in switcher
      expect(find.text('Схема'), findsOneWidget);
      expect(find.text('Рентген'), findsOneWidget);
      expect(find.text('Аналогия'), findsOneWidget);

      // Verify Schema tab content
      expect(find.textContaining('1 · Вы написали'), findsOneWidget);
      expect(find.textContaining('2 · Приложение собрало запрос'), findsOneWidget);
      expect(find.textContaining('3 · Сервер CraftAI'), findsOneWidget);
      expect(find.textContaining('4 · Модель «Рабочая»'), findsOneWidget);
      expect(find.textContaining('5 · Ответ на телефоне'), findsOneWidget);

      // Verify metrics row
      expect(find.text('748'), findsOneWidget);
      expect(find.text('токенов'), findsOneWidget);
      expect(find.text('4.6 с'), findsOneWidget);
      expect(find.text('●●○'), findsOneWidget);
    });

    testWidgets('switches to S31b X-ray tab and displays layer breakdown with server badge', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final traceRepo = InMemoryTraceRepository();
      final sample = PersistentTraceRepository.createSampleFixture();
      await traceRepo.saveTrace(sample);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            traceRepositoryProvider.overrideWithValue(traceRepo),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: TraceSheet(requestId: 'sample-trace-748'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to X-ray tab
      await tester.tap(find.text('Рентген'));
      await tester.pumpAndSettle();

      // Verify X-ray subtitle & server badge
      expect(find.textContaining('Всё, что модель увидела в момент ответа'), findsOneWidget);
      expect(find.text('Сервер'), findsOneWidget);

      // Verify layers
      expect(find.text('1 · Инструкция v3'), findsOneWidget);
      expect(find.text('2 · Память'), findsOneWidget);
      expect(find.text('3 · Найдено в документах'), findsOneWidget);
      expect(find.text('4 · Ваш вопрос'), findsOneWidget);
      expect(find.text('Текст ответа'), findsOneWidget);

      // Verify token counts
      expect(find.text('180 ток.'), findsOneWidget);
      expect(find.text('24 ток.'), findsOneWidget);
      expect(find.text('310 ток.'), findsOneWidget);
      expect(find.text('212 ток.'), findsOneWidget);
    });

    testWidgets('switches to S31c Analogy tab and displays editorial content', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final traceRepo = InMemoryTraceRepository();
      final sample = PersistentTraceRepository.createSampleFixture();
      await traceRepo.saveTrace(sample);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            traceRepositoryProvider.overrideWithValue(traceRepo),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: TraceSheet(requestId: 'sample-trace-748'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Analogy tab
      await tester.tap(find.text('Аналогия'));
      await tester.pumpAndSettle();

      // Verify story & comparison rows
      expect(find.text('Секретарь и эксперт'), findsOneWidget);
      expect(find.text('В жизни → в ассистенте'), findsOneWidget);
      expect(find.text('Секретарь'), findsOneWidget);
      expect(find.text('Приложение'), findsOneWidget);
      expect(find.text('Папка с вашими правилами'), findsOneWidget);
      expect(find.text('Инструкция'), findsOneWidget);
      expect(find.text('Блокнот с фактами о классе'), findsOneWidget);
      expect(find.text('Память'), findsOneWidget);

      // Verify takeaway
      expect(find.textContaining('Главное:'), findsOneWidget);
    });

    testWidgets('displays aborted and error trace states properly', (tester) async {
      final traceRepo = InMemoryTraceRepository();
      final interruptedTrace = RequestTrace.fromExecution(
        requestId: 'req_aborted',
        ownerId: 'owner_f08',
        conversationId: 'c1',
        modelCategory: 'standard',
        assistantVersion: 1,
        userPrompt: 'Длинный рассказ',
        responseText: 'Начало рассказа...',
        durationMs: 3200,
        status: TraceStatus.interrupted,
      );
      await traceRepo.saveTrace(interruptedTrace);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            traceRepositoryProvider.overrideWithValue(traceRepo),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: TraceSheet(requestId: 'req_aborted'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Запрос был остановлен'), findsOneWidget);
      expect(find.text('Пользователь вручную прервал генерацию ответа.'), findsOneWidget);
    });

    testWidgets('tapping trace icon on assistant message bubble opens TraceSheet', (tester) async {
      final chatRepo = InMemoryChatRepository();
      final traceRepo = InMemoryTraceRepository();
      final policyRepo = MockPolicyRepository();

      final conv = await chatRepo.createConversation(
        ownerId: 'owner_f08',
        title: 'Тест трассы',
        retentionPolicy: RetentionPolicy.persistent,
      );

      final assistantMsg = ChatMessage(
        id: 'msg_assist_1',
        conversationId: conv.id,
        ownerId: 'owner_f08',
        role: MessageRole.assistant,
        content: 'Вот готовый ответ ассистента.',
        status: MessageStatus.completed,
        requestId: 'req_trace_flow',
        createdAtUtc: DateTime.now().toUtc(),
      );
      await chatRepo.saveMessage(assistantMsg);

      final trace = RequestTrace.fromExecution(
        requestId: 'req_trace_flow',
        ownerId: 'owner_f08',
        conversationId: conv.id,
        modelCategory: 'standard',
        assistantVersion: 1,
        userPrompt: 'Вопрос пользователя',
        responseText: 'Вот готовый ответ ассистента.',
        durationMs: 1500,
        status: TraceStatus.completed,
      );
      await traceRepo.saveTrace(trace);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatRepositoryProvider.overrideWithValue(chatRepo),
            traceRepositoryProvider.overrideWithValue(traceRepo),
            policyRepositoryProvider.overrideWithValue(policyRepo),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AssistantPage(ownerId: 'owner_f08'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the trace icon button
      final traceBtnFinder = find.byKey(const Key('chat.traceBtn_msg_assist_1'));
      expect(traceBtnFinder, findsOneWidget);

      // Tap trace button
      await tester.tap(traceBtnFinder);
      await tester.pumpAndSettle();

      // Verify TraceSheet opened
      expect(find.byType(TraceSheet), findsOneWidget);
      expect(find.text('Под капотом'), findsOneWidget);
      expect(find.text('Схема'), findsOneWidget);
    });
  });
}
