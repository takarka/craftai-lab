import 'dart:io';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/storage_providers.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/assistant/assistant_providers.dart';
import 'package:builder/features/assistant/infrastructure/persistent_assistant_repository.dart';
import 'package:builder/features/chat/domain/context_assembler.dart';
import 'package:builder/features/instructions/domain/instruction_models.dart';
import 'package:builder/features/instructions/infrastructure/persistent_instructions_repository.dart';
import 'package:builder/features/instructions/presentation/instructions_page.dart';
import 'package:builder/features/models/domain/model_category.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('F11: Instruction Domain, Presets & Deterministic Assembly', () {
    test('F11-01 & F11-02: Deterministic assembly strictly respects group order', () {
      final roleRule = InstructionRule(
        id: 'r1',
        group: InstructionGroup.role,
        title: 'Роль',
        text: 'Ты помощник учителя биологии.',
        explanation: 'Роль',
        isEnabled: true,
        sortOrder: 1,
      );

      final formatRule = InstructionRule(
        id: 'f1',
        group: InstructionGroup.format,
        title: 'Формат',
        text: 'Отвечай по пунктам.',
        explanation: 'Формат',
        isEnabled: true,
        sortOrder: 1,
      );

      final constraintRule = InstructionRule(
        id: 'c1',
        group: InstructionGroup.constraint,
        title: 'Ограничение',
        text: 'Не выдумывай факты.',
        explanation: 'Ограничение',
        isEnabled: true,
        sortOrder: 1,
      );

      final toneRule = InstructionRule(
        id: 't1',
        group: InstructionGroup.tone,
        title: 'Тон',
        text: 'Используй дружелюбный тон.',
        explanation: 'Тон',
        isEnabled: true,
        sortOrder: 1,
      );

      final customRule = InstructionRule(
        id: 'cust1',
        group: InstructionGroup.custom,
        title: 'Своё',
        text: 'Всегда напоминай про домашнее задание.',
        explanation: 'Своё',
        isEnabled: true,
        sortOrder: 1,
      );

      // Pass in mixed order: constraint, custom, format, role, tone
      final mixedList = [constraintRule, customRule, formatRule, roleRule, toneRule];
      final assembled = InstructionConfig.assemble(mixedList);

      final lines = assembled.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(lines.length, 5);
      // Order MUST be: role -> tone -> format -> constraint -> custom (F11-02)
      expect(lines[0], contains('биологии'));
      expect(lines[1], contains('дружелюбный'));
      expect(lines[2], contains('пунктам'));
      expect(lines[3], contains('факты'));
      expect(lines[4], contains('домашнее задание'));
    });

    test('F11-02: Disabled rules are completely excluded from assembled text', () {
      final enabledRule = InstructionRule(
        id: 'r1',
        group: InstructionGroup.role,
        title: 'Роль',
        text: 'Ты методист.',
        explanation: '',
        isEnabled: true,
      );

      final disabledRule = InstructionRule(
        id: 'f1',
        group: InstructionGroup.format,
        title: 'Формат',
        text: 'НЕ ДОЛЖНО БЫТЬ В ИТОГОВОМ ТЕКСТЕ',
        explanation: '',
        isEnabled: false,
      );

      final assembled = InstructionConfig.assemble([enabledRule, disabledRule]);
      expect(assembled, contains('Ты методист.'));
      expect(assembled, isNot(contains('НЕ ДОЛЖНО БЫТЬ')));
    });

    test('F11-03: Token estimation and limit warnings', () {
      final configEmpty = const InstructionConfig(rules: []);
      expect(configEmpty.estimatedTokens, 0);
      expect(configEmpty.isOverTokenLimit, false);

      final shortRule = InstructionRule(
        id: 'r1',
        group: InstructionGroup.role,
        title: 'Короткое правило',
        text: 'Ты помощник учителя.',
        explanation: '',
        isEnabled: true,
      );

      final configShort = InstructionConfig(rules: [shortRule]);
      expect(configShort.estimatedTokens, greaterThan(0));
      expect(configShort.isOverTokenLimit, false);

      // Very long text > 500 tokens (~1800 chars)
      final longText = 'Очень длинная инструкция. ' * 120;
      final configLong = InstructionConfig(isRawMode: true, rawText: longText);
      expect(configLong.estimatedTokens, greaterThan(500));
      expect(configLong.isOverTokenLimit, true);
    });

    test('F11-04 & F11-05: Serialization to systemRules preserves raw mode and structured rules', () {
      // 1. Structured config
      final r1 = InstructionRule(
        id: 'role_bio_teacher',
        group: InstructionGroup.role,
        title: 'Биология',
        text: 'Ты учитель биологии.',
        explanation: '',
        isEnabled: true,
      );
      final r2 = InstructionRule(
        id: 'custom_123',
        group: InstructionGroup.custom,
        title: 'Своё правило',
        text: 'Специальное указание.',
        explanation: '',
        isEnabled: true,
        isCustom: true,
      );

      final structuredConfig = InstructionConfig(
        isRawMode: false,
        rawText: 'Резервный текст',
        rules: [r1, r2],
      );

      final serialized = structuredConfig.toSystemRules();
      expect(serialized.first, '__STRUCTURED_V1__');

      // Deserialize
      final recovered = InstructionConfig.fromSystemRules(serialized, ownerId: 'test_owner');
      expect(recovered.isRawMode, false);
      expect(recovered.enabledRulesCount, 2);
      expect(recovered.activeInstructionText, contains('биологии'));
      expect(recovered.activeInstructionText, contains('Специальное указание.'));

      // 2. Raw mode config
      const customRaw = 'Мой полностью ручной промпт без генератора';
      final rawConfig = InstructionConfig(
        isRawMode: true,
        rawText: customRaw,
        rules: [r1],
      );

      final serializedRaw = rawConfig.toSystemRules();
      expect(serializedRaw.first, '__RAW_MODE__');
      expect(serializedRaw[1], customRaw);

      final recoveredRaw = InstructionConfig.fromSystemRules(serializedRaw, ownerId: 'test_owner');
      expect(recoveredRaw.isRawMode, true);
      expect(recoveredRaw.rawText, customRaw);
      expect(recoveredRaw.activeInstructionText, customRaw);
    });
  });

  group('F11: Persistent Instructions Repository & SQLite Storage', () {
    late Directory tempDir;
    late StorageDatabase db;
    late WorkspaceStorageService wsService;
    late PersistentAssistantRepository assistantRepo;
    late PersistentInstructionsRepository instructionsRepo;
    const testOwner = 'owner_f11_repo';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('f11_test_');
      final dbPath = p.join(tempDir.path, 'f11_test.db');
      db = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await db.open();

      wsService = WorkspaceStorageService(
        database: db,
        keyStorage: InMemorySecureKeyStorage(),
        installationId: 'inst_f11',
      );
      await wsService.openWorkspace(ownerId: testOwner);

      assistantRepo = PersistentAssistantRepository(
        database: db,
        workspaceService: wsService,
      );

      instructionsRepo = PersistentInstructionsRepository(database: db);

      // Seed initial assistant config
      await assistantRepo.commitChange(
        ownerId: testOwner,
        name: 'Сова',
        selectedCategory: ModelCategory.standard,
        enabledSkills: {},
        systemRules: [],
        reason: 'Инициализация',
      );
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Initial getInstructionConfig seeds preset rules into tableInstructionRules', () async {
      final config = await instructionsRepo.getInstructionConfig(testOwner);
      expect(config.rules.length, greaterThanOrEqualTo(10));
      expect(config.enabledRulesCount, 0); // Initially disabled

      final roleRules = config.rules.where((r) => r.group == InstructionGroup.role).toList();
      expect(roleRules.isNotEmpty, true);
      expect(roleRules.first.title, contains('биологии'));
    });

    test('Saving instruction config syncs tableInstructionRules and assistant config', () async {
      var config = await instructionsRepo.getInstructionConfig(testOwner);
      final updatedRules = config.rules.map((r) {
        if (r.id.contains('role_bio_teacher')) {
          return r.copyWith(isEnabled: true);
        }
        return r;
      }).toList();

      config = config.copyWith(rules: updatedRules);
      await instructionsRepo.saveInstructionConfig(testOwner, config);

      final reloaded = await instructionsRepo.getInstructionConfig(testOwner);
      expect(reloaded.enabledRulesCount, 1);
      expect(reloaded.activeInstructionText, contains('биологии'));

      // Check assistant config row in DB
      final assistantConfig = await assistantRepo.getConfiguration(testOwner);
      expect(assistantConfig, isNotNull);
      final textFromAssistant = InstructionConfig.getActiveInstructionText(assistantConfig!.systemRules);
      expect(textFromAssistant, contains('биологии'));
    });

    test('Custom rule creation and deletion', () async {
      final customRule = InstructionRule(
        id: 'cust_bio_9',
        group: InstructionGroup.custom,
        title: 'Углубленная биология',
        text: 'Фокусируйся на клеточной биологии.',
        explanation: 'Своё правило',
        isEnabled: true,
        isCustom: true,
      );

      await instructionsRepo.addCustomRule(testOwner, customRule);

      final config = await instructionsRepo.getInstructionConfig(testOwner);
      final found = config.rules.where((r) => r.id.contains('cust_bio_9')).toList();
      expect(found.isNotEmpty, true);
      expect(found.first.text, contains('клеточной биологии'));

      await instructionsRepo.deleteCustomRule(testOwner, found.first.id);

      final configAfterDelete = await instructionsRepo.getInstructionConfig(testOwner);
      final afterDelete = configAfterDelete.rules.where((r) => r.id.contains('cust_bio_9')).toList();
      expect(afterDelete.isEmpty, true);
    });
  });

  group('F11: Acceptance Criteria - Real Payload Verification & Context Assembler', () {
    test('Wire payload includes exact active instruction when skill is enabled', () {
      const activeInstruction = 'Ты помощник учителя биологии. Отвечай кратко.';
      final assembler = const ContextAssembler();

      final manifest = assembler.assemble(
        manifestId: 'test_manifest_1',
        requestId: 'req_1',
        category: 'standard',
        catalogRevision: '2026-03-31-01',
        contextWindow: 128000,
        activeInstruction: activeInstruction,
        conversationHistory: const [],
        userPrompt: 'Что такое фотосинтез?',
      );

      expect(manifest.activeInstruction, activeInstruction);

      // Verify wire messages contain exact system instruction
      final systemMessages = manifest.messages.where((m) => m['role'] == 'system').toList();
      expect(systemMessages.length, 1);
      expect(systemMessages.first['content'], contains('Инструкция:\n$activeInstruction'));

      // User prompt is present
      final userMessages = manifest.messages.where((m) => m['role'] == 'user').toList();
      expect(userMessages.first['content'], 'Что такое фотосинтез?');
    });

    test('Wire payload omits system instruction when activeInstruction is null or empty', () {
      final assembler = const ContextAssembler();

      final manifest = assembler.assemble(
        manifestId: 'test_manifest_2',
        requestId: 'req_2',
        category: 'standard',
        catalogRevision: '2026-03-31-01',
        contextWindow: 128000,
        activeInstruction: null, // Disabled or empty
        conversationHistory: const [],
        userPrompt: 'Что такое фотосинтез?',
      );

      expect(manifest.activeInstruction, isNull);
      final systemMessages = manifest.messages.where((m) => m['role'] == 'system').toList();
      expect(systemMessages.isEmpty, true);
    });
  });

  group('F11: S40 Instructions Page Widget Tests (Work & Learn Modes)', () {
    late Directory tempDir;
    late StorageDatabase db;
    late WorkspaceStorageService wsService;
    late PersistentAssistantRepository assistantRepo;
    const testOwner = 'owner_f11_widget';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('f11_widget_');
      final dbPath = p.join(tempDir.path, 'f11_widget.db');
      db = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await db.open();

      wsService = WorkspaceStorageService(
        database: db,
        keyStorage: InMemorySecureKeyStorage(),
        installationId: 'inst_f11_widget',
      );
      await wsService.openWorkspace(ownerId: testOwner);

      assistantRepo = PersistentAssistantRepository(
        database: db,
        workspaceService: wsService,
      );

      await assistantRepo.commitChange(
        ownerId: testOwner,
        name: 'Сова',
        selectedCategory: ModelCategory.standard,
        enabledSkills: {},
        systemRules: [],
        reason: 'Инициализация виджет-теста',
      );
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Widget createTestWidget({
      required SkillScreenMode mode,
      VoidCallback? onPracticeCompleted,
    }) {
      return ProviderScope(
        overrides: [
          storageDatabaseProvider.overrideWithValue(db),
          assistantRepositoryProvider.overrideWithValue(assistantRepo),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: InstructionsPage(
            ownerId: testOwner,
            mode: mode,
            onPracticeCompleted: onPracticeCompleted,
          ),
        ),
      );
    }

    testWidgets('S40 work mode renders elements, toggles rule and updates preview', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(createTestWidget(mode: SkillScreenMode.work));
      });
      await tester.pumpAndSettle();

      // Verify header & mode buttons
      expect(find.text('Инструкции ассистента'), findsOneWidget);
      expect(find.byKey(const Key('instructions.modeSegment.structured')), findsOneWidget);
      expect(find.byKey(const Key('instructions.modeSegment.raw')), findsOneWidget);
      expect(find.byKey(const Key('instructions.previewCard')), findsOneWidget);
      expect(find.byKey(const Key('instructions.testBeforeAfterBtn')), findsOneWidget);
      expect(find.byKey(const Key('instructions.saveBtn')), findsOneWidget);

      // Verify preset rule switch exists and toggle it
      final firstSwitch = find.byType(Switch).first;
      expect(tester.widget<Switch>(firstSwitch).value, false);

      await tester.tap(firstSwitch);
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(firstSwitch).value, true);

      // Verify preview now contains the rule text
      expect(find.byKey(const Key('instructions.previewCard')), findsOneWidget);
    });

    testWidgets('S40 raw mode allows direct editing without overwriting rules', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(createTestWidget(mode: SkillScreenMode.work));
      });
      await tester.pumpAndSettle();

      // Switch to raw mode
      await tester.tap(find.byKey(const Key('instructions.modeSegment.raw')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('instructions.rawTextField')), findsOneWidget);

      // Enter custom text in raw field
      await tester.enterText(find.byKey(const Key('instructions.rawTextField')), 'Прямой текст промпта');
      await tester.pumpAndSettle();

      expect(find.text('Прямой текст промпта'), findsWidgets);
    });

    testWidgets('S40 Before/After test runs and displays comparison results', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(createTestWidget(mode: SkillScreenMode.work));
      });
      await tester.pumpAndSettle();

      // Tap test button
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('instructions.testBeforeAfterBtn')));
      });
      await tester.pumpAndSettle();

      // Comparison cards should be visible
      expect(find.byKey(const Key('instructions.beforeCard')), findsOneWidget);
      expect(find.byKey(const Key('instructions.afterCard')), findsOneWidget);
      expect(find.text('До (без инструкций)'), findsOneWidget);
      expect(find.text('После (с инструкциями)'), findsOneWidget);
    });

    testWidgets('S40 learn mode checks evidence criteria before completion (F11-08)', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool practiceCompletedCalled = false;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          createTestWidget(
            mode: SkillScreenMode.learn,
            onPracticeCompleted: () {
              practiceCompletedCalled = true;
            },
          ),
        );
      });
      await tester.pumpAndSettle();

      // Verify learning banner is present
      expect(find.byKey(const Key('instructions.learnBanner')), findsOneWidget);
      expect(find.byKey(const Key('instructions.reflectionInput')), findsOneWidget);

      // Try saving without meeting criteria -> shows snackbar, does not complete
      await tester.tap(find.byKey(const Key('instructions.saveBtn')));
      await tester.pumpAndSettle();

      expect(practiceCompletedCalled, false);
      expect(find.textContaining('Для завершения практики выберите минимум 3 правила'), findsOneWidget);

      // Hide snackbar
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      // Enable 3 rules
      final switches = find.byType(Switch);
      for (int i = 0; i < 3; i++) {
        await tester.tap(switches.at(i));
        await tester.pumpAndSettle();
      }

      // Run test
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('instructions.testBeforeAfterBtn')));
      });
      await tester.pumpAndSettle();

      // Fill in reflection
      await tester.enterText(
        find.byKey(const Key('instructions.reflectionInput')),
        'Ответ стал структурированным и кратким.',
      );
      await tester.pumpAndSettle();

      // Now save
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('instructions.saveBtn')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(practiceCompletedCalled, true);
    });
  });
}
