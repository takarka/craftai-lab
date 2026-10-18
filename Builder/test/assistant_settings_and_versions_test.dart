import 'dart:convert';
import 'dart:io';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/ui_kit/ui_kit.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/storage_providers.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/assistant/assistant_providers.dart';
import 'package:builder/features/assistant/domain/assistant_config.dart';
import 'package:builder/features/assistant/infrastructure/persistent_assistant_repository.dart';
import 'package:builder/features/assistant/presentation/assistant_name_page.dart';
import 'package:builder/features/assistant/presentation/assistant_page.dart';
import 'package:builder/features/assistant/presentation/assistant_settings_page.dart';
import 'package:builder/features/assistant/presentation/assistant_versions_page.dart';
import 'package:builder/features/assistant/presentation/local_data_settings_page.dart';
import 'package:builder/features/assistant/presentation/reset_confirmation_dialog.dart';
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

  group('F09: Assistant Repository & Domain Logic', () {
    late Directory tempDir;
    late StorageDatabase db;
    late WorkspaceStorageService wsService;
    late PersistentAssistantRepository repo;
    const testOwner = 'test_owner_f09';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('f09_test_');
      final dbPath = p.join(tempDir.path, 'f09_test.db');
      db = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await db.open();

      wsService = WorkspaceStorageService(
        database: db,
        keyStorage: InMemorySecureKeyStorage(),
        installationId: 'test_inst_1',
      );
      await wsService.openWorkspace(ownerId: testOwner);

      repo = PersistentAssistantRepository(
        database: db,
        workspaceService: wsService,
      );

      // Seed initial workspace config
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      await db.db.insert(StorageSchemaV1.tableAssistantConfigurations, {
        'owner_id': testOwner,
        'name': 'Сова',
        'selected_category': 'standard',
        'enabled_skills_json': '["instructions"]',
        'system_rules_json': '["Отвечать кратко"]',
        'state_revision': 1,
        'updated_at_utc': nowUtc,
      });

      await db.db.insert(StorageSchemaV1.tableTeacherPreferences, {
        'owner_id': testOwner,
        'subject': 'math',
        'grades_json': '[5, 6]',
        'ui_language': 'ru',
        'assistant_language': 'ru',
        'reminders_enabled': 0,
        'storage_retention_days': 30,
        'updated_at_utc': nowUtc,
      });
    });

    tearDown(() async {
      await wsService.closeActiveWorkspace();
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'F09-03 & F09-06: Seeds initial version v1 if none exists, returns sorted versions',
      () async {
        final versions = await repo.getVersions(testOwner);
        expect(versions, hasLength(1));
        expect(versions.first.versionNumber, equals(1));
        expect(versions.first.reason, equals('Создание ассистента'));
        expect(versions.first.isCurrent, isTrue);
        expect(versions.first.snapshot.name, equals('Сова'));
      },
    );

    test(
      'F09-03: CommitAssistantChange increments version and state revision with human readable reason',
      () async {
        // First ensure v1 exists
        await repo.getVersions(testOwner);

        final v2 = await repo.commitChange(
          ownerId: testOwner,
          name: 'Сова Мудрая',
          selectedCategory: ModelCategory.fast,
          enabledSkills: {'instructions', 'knowledge'},
          systemRules: ['Отвечать кратко', 'Использовать примеры'],
          reason: 'Изменение имени на «Сова Мудрая»',
        );

        expect(v2.versionNumber, equals(2));
        expect(v2.reason, equals('Изменение имени на «Сова Мудрая»'));
        expect(v2.snapshot.name, equals('Сова Мудрая'));
        expect(v2.snapshot.selectedCategory, equals(ModelCategory.fast));
        expect(v2.snapshot.enabledSkills, contains('knowledge'));

        final config = await repo.getConfiguration(testOwner);
        expect(config?.name, equals('Сова Мудрая'));
        expect(config?.stateRevision, equals(3));

        final allVersions = await repo.getVersions(testOwner);
        expect(allVersions, hasLength(2));
        expect(allVersions.first.versionNumber, equals(2));
        expect(allVersions.first.isCurrent, isTrue);
        expect(allVersions[1].isCurrent, isFalse);
      },
    );

    test(
      'F09-06 & ADR-02: Identifies permanently deleted documents as missing resources',
      () async {
        final nowUtc = DateTime.now().toUtc().toIso8601String();
        // Insert a document
        await db.db.insert(StorageSchemaV1.tableKnowledgeDocuments, {
          'id': 'doc_temp_1',
          'owner_id': testOwner,
          'content_hash': 'hash_123',
          'file_name': 'План урока.pdf',
          'file_format': 'pdf',
          'file_size_bytes': 1024,
          'is_enabled': 1,
          'index_status': 'ready',
          'created_at_utc': nowUtc,
        });

        // Commit a version that captures this doc
        await repo.commitChange(
          ownerId: testOwner,
          name: 'Сова',
          selectedCategory: ModelCategory.standard,
          enabledSkills: {'instructions'},
          reason: 'Добавлен документ',
        );

        var versions = await repo.getVersions(testOwner);
        expect(versions.first.missingResources, isEmpty);

        // Now permanently delete the document (ADR-02)
        await db.db.delete(
          StorageSchemaV1.tableKnowledgeDocuments,
          where: 'id = ?',
          whereArgs: ['doc_temp_1'],
        );

        versions = await repo.getVersions(testOwner);
        expect(versions.first.missingResources, contains('doc_temp_1'));
      },
    );

    test(
      'F09-07 & F09-08: Rollback restores snapshot and blocks unearned course capabilities',
      () async {
        // Initial v1
        await repo.getVersions(testOwner);

        // Version 2 has memory (requires level 3) and tools (requires level 5)
        await repo.commitChange(
          ownerId: testOwner,
          name: 'Сова Продвинутая',
          selectedCategory: ModelCategory.advanced,
          enabledSkills: {'instructions', 'knowledge', 'memory', 'tools'},
          reason: 'Включение всех умений',
        );

        // Assume user has only completed up to Level 2 (instructions & knowledge are allowed)
        final allowedSkills = {'instructions', 'knowledge'};

        await repo.rollbackToVersion(
          ownerId: testOwner,
          targetVersionNumber: 2,
          allowedSkills: allowedSkills,
        );

        final config = await repo.getConfiguration(testOwner);
        expect(config?.name, equals('Сова Продвинутая'));
        expect(config?.selectedCategory, equals(ModelCategory.advanced));
        // Memory and tools must be stripped because course level was not completed!
        expect(config?.enabledSkills, equals({'instructions', 'knowledge'}));

        // Version history contains new rollback version 3 without deleting history
        final versions = await repo.getVersions(testOwner);
        expect(versions, hasLength(3));
        expect(versions.first.versionNumber, equals(3));
        expect(versions.first.reason, equals('Восстановление версии 2'));
      },
    );

    test(
      'F09-09: LocalDataSummary accurately aggregates table counts',
      () async {
        final nowUtc = DateTime.now().toUtc().toIso8601String();
        await db.db.insert(StorageSchemaV1.tableConversations, {
          'id': 'conv_1',
          'owner_id': testOwner,
          'title': 'Первый урок',
          'created_at_utc': nowUtc,
          'activity_at_utc': nowUtc,
          'retention_policy': 'indefinite',
        });
        await db.db.insert(StorageSchemaV1.tableMessages, {
          'id': 'msg_1',
          'conversation_id': 'conv_1',
          'owner_id': testOwner,
          'role': 'user',
          'content': 'Привет',
          'status': 'sent',
          'created_at_utc': nowUtc,
        });
        await db.db.insert(StorageSchemaV1.tableMemoryFacts, {
          'id': 'fact_1',
          'owner_id': testOwner,
          'fact_text': '7Б класс изучает дроби',
          'source': 'chat',
          'is_enabled': 1,
          'created_at_utc': nowUtc,
          'updated_at_utc': nowUtc,
        });

        final summary = await repo.getLocalDataSummary(testOwner);
        expect(summary.conversationsCount, equals(1));
        expect(summary.messagesCount, equals(1));
        expect(summary.memoryFactsCount, equals(1));
      },
    );

    test(
      'F09-10: ResetAssistantWorkspace advances epoch and cleans all local tables',
      () async {
        final initialEpoch = wsService.activeEpoch!;

        await repo.resetAssistantWorkspace(testOwner);

        // Epoch fence must be incremented
        expect(wsService.activeEpoch, equals(initialEpoch + 1));

        // Tables must be empty for owner
        final versions = await db.db.query(
          StorageSchemaV1.tableAssistantVersions,
          where: 'owner_id = ?',
          whereArgs: [testOwner],
        );
        expect(versions, isEmpty);

        final convs = await db.db.query(
          StorageSchemaV1.tableConversations,
          where: 'owner_id = ?',
          whereArgs: [testOwner],
        );
        expect(convs, isEmpty);

        // Configuration name is reset to empty baseline
        final config = await repo.getConfiguration(testOwner);
        expect(config?.name, isEmpty);
        expect(config?.selectedCategory, isNull);
        expect(config?.enabledSkills, isEmpty);
      },
    );
  });

  group('F09: Assistant Presentation & UI Workflows', () {
    late Directory tempDir;
    late StorageDatabase db;
    late WorkspaceStorageService wsService;
    late PersistentAssistantRepository repo;
    const testOwner = 'test_owner_ui_f09';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('f09_ui_test_');
      final dbPath = p.join(tempDir.path, 'f09_ui.db');
      db = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await db.open();

      wsService = WorkspaceStorageService(
        database: db,
        keyStorage: InMemorySecureKeyStorage(),
        installationId: 'test_inst_ui',
      );
      await wsService.openWorkspace(ownerId: testOwner);
      repo = PersistentAssistantRepository(
        database: db,
        workspaceService: wsService,
      );

      final nowUtc = DateTime.now().toUtc().toIso8601String();
      await db.db.insert(StorageSchemaV1.tableAssistantConfigurations, {
        'owner_id': testOwner,
        'name': 'Арлан',
        'selected_category': 'standard',
        'enabled_skills_json': '["instructions"]',
        'system_rules_json': '[]',
        'state_revision': 1,
        'updated_at_utc': nowUtc,
      });

      await db.db.insert(StorageSchemaV1.tableAssistantVersions, {
        'owner_id': testOwner,
        'version_number': 1,
        'created_at_utc': nowUtc,
        'reason': 'Создание ассистента',
        'parent_id': null,
        'schema_version': 1,
        'snapshot_json': jsonEncode({
          'name': 'Арлан',
          'selected_category': 'standard',
          'enabled_skills': ['instructions'],
          'system_rules': <String>[],
          'memory_facts_count': 0,
          'documents_count': 0,
          'document_ids': <String>[],
        }),
      });

      await db.db.insert(StorageSchemaV1.tableTeacherPreferences, {
        'owner_id': testOwner,
        'subject': 'history',
        'grades_json': '[7, 8]',
        'ui_language': 'ru',
        'assistant_language': 'ru',
        'reminders_enabled': 0,
        'storage_retention_days': 30,
        'updated_at_utc': nowUtc,
      });
    });

    tearDown(() async {
      await wsService.closeActiveWorkspace();
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Widget createTestApp(
      Widget child, {
      AssistantConfig? initialConfig,
      List<AssistantVersion>? versions,
      Set<int>? completedLevels,
    }) {
      final config =
          initialConfig ??
          AssistantConfig(
            ownerId: testOwner,
            name: 'Арлан',
            selectedCategory: ModelCategory.standard,
            enabledSkills: const {'instructions'},
            systemRules: const [],
            stateRevision: 1,
            updatedAtUtc: DateTime.now().toUtc(),
          );

      final versionItems =
          versions ??
          [
            AssistantVersion(
              versionNumber: 1,
              createdAtUtc: DateTime.now().toUtc(),
              reason: 'Создание ассистента',
              snapshot: const AssistantSnapshot(
                name: 'Арлан',
                selectedCategory: ModelCategory.standard,
                enabledSkills: {'instructions'},
              ),
              isCurrent: true,
            ),
          ];

      return ProviderScope(
        overrides: [
          storageDatabaseProvider.overrideWithValue(db),
          workspaceStorageServiceProvider.overrideWithValue(wsService),
          assistantRepositoryProvider.overrideWithValue(repo),
          assistantConfigProvider(testOwner).overrideWith((ref) => config),
          assistantVersionsProvider(
            testOwner,
          ).overrideWith((ref) => versionItems),
          localDataSummaryProvider(testOwner).overrideWith(
            (ref) => const LocalDataSummary(
              conversationsCount: 1,
              messagesCount: 2,
              memoryFactsCount: 3,
              documentsCount: 4,
              chunksCount: 12,
              tracesCount: 5,
              versionsCount: 1,
            ),
          ),
          completedCourseLevelsProvider(
            testOwner,
          ).overrideWith((ref) => completedLevels ?? {1}),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru'), Locale('kk')],
          locale: const Locale('ru'),
          home: child,
        ),
      );
    }

    testWidgets(
      'F09-01 & F09-V01: S11 renders assistant card, model row, instructions, and 8 skills',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(const AssistantSettingsPage(ownerId: testOwner)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Assistant name and level
        expect(find.text('Арлан'), findsOneWidget);
        expect(find.text('Уровень 1 из 5'), findsOneWidget);

        // Model row
        expect(
          find.byKey(const Key('assistantSettings.modelRow')),
          findsOneWidget,
        );

        // Instructions card and versions link
        expect(
          find.byKey(const Key('assistantSettings.versionsLink')),
          findsOneWidget,
        );
        expect(find.text('История версий · v1'), findsOneWidget);

        // 8 skills rendered
        for (final skill in AssistantSkillId.values) {
          expect(find.byKey(Key('skill.card.${skill.id}')), findsOneWidget);
        }

        // Coming soon skills (6–9) are labeled "После MVP · скоро"
        expect(find.text('После MVP · скоро'), findsNWidgets(4));

        // Reset button exists
        expect(
          find.byKey(const Key('assistantSettings.resetBtn')),
          findsOneWidget,
        );
      },
    );

    for (var level = 0; level <= 5; level++) {
      testWidgets('Settings feature buttons respect completed level $level', (
        tester,
      ) async {
        await tester.pumpWidget(
          createTestApp(
            const AssistantSettingsPage(ownerId: testOwner),
            completedLevels: {for (var n = 1; n <= level; n++) n},
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        for (final feature in [
          AssistantSkillId.instructions,
          AssistantSkillId.knowledge,
          AssistantSkillId.memory,
          AssistantSkillId.tools,
        ]) {
          final card = tester.widget<BuilderSkillCard>(
            find.byKey(Key('skill.card.${feature.id}')),
          );
          expect(
            card.onTap != null,
            level >= feature.level,
            reason: '${feature.id} unlocks after ${feature.level}',
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
    testWidgets(
      'F16-04: S11 renders assistant language row and opens language selection sheet',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(const AssistantSettingsPage(ownerId: testOwner)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        final languageRow = find.byKey(
          const Key('assistantSettings.languageRow'),
        );
        expect(languageRow, findsOneWidget);
        expect(find.textContaining('Язык ответов ассистента'), findsOneWidget);

        await tester.tap(languageRow);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('assistantLanguage.radio.russian')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('assistantLanguage.radio.kazakh')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('assistantLanguage.radio.bilingual')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('assistantLanguage.saveBtn')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('assistantLanguage.cancelBtn')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('assistantLanguage.saveBtn')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'F09-02 & F09-V02: S14 validates graphemes (max 30) and saves draft',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(const AssistantNamePage(ownerId: testOwner)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        final input = find.byKey(const Key('assistant.nameField'));
        expect(input, findsOneWidget);

        // Enter a name that exceeds 30 characters
        const tooLongName =
            'ОченьДлинноеИмяАссистентаКотороеПревышаетЛимитВТридцатьСимволов';
        await tester.enterText(input, tooLongName);
        await tester.pumpAndSettle();

        expect(find.text('Имя превышает 30 символов'), findsOneWidget);
        final saveBtn = tester.widget<TextButton>(
          find.descendant(
            of: find.byKey(const Key('assistant.nameSaveBtn')),
            matching: find.byType(TextButton),
          ),
        );
        expect(saveBtn.onPressed, isNull); // Disabled!

        // Enter valid name
        await tester.enterText(input, 'Новый Ментор');
        await tester.pumpAndSettle();

        expect(find.text('Имя превышает 30 символов'), findsNothing);
        expect(find.text('12 / 30'), findsOneWidget);

        await tester.tap(find.byKey(const Key('assistant.nameSaveBtn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        // Check repository committed change
        final config = await tester.runAsync(
          () => repo.getConfiguration(testOwner),
        );
        expect(config?.name, equals('Новый Ментор'));
      },
    );

    testWidgets(
      'F09-06 & F09-07: S12 displays versions, current tag, and rollback dialog',
      (tester) async {
        // Add version 2 in real async
        await tester.runAsync(() async {
          await repo.commitChange(
            ownerId: testOwner,
            name: 'Арлан Обновлённый',
            selectedCategory: ModelCategory.fast,
            enabledSkills: {'instructions'},
            reason: 'Обновление настроек',
          );
        });

        final versionsList = [
          AssistantVersion(
            versionNumber: 2,
            createdAtUtc: DateTime.now().toUtc(),
            reason: 'Обновление настроек',
            snapshot: const AssistantSnapshot(
              name: 'Арлан Обновлённый',
              selectedCategory: ModelCategory.fast,
              enabledSkills: {'instructions'},
            ),
            isCurrent: true,
          ),
          AssistantVersion(
            versionNumber: 1,
            createdAtUtc: DateTime.now().toUtc().subtract(
              const Duration(hours: 1),
            ),
            reason: 'Создание ассистента',
            snapshot: const AssistantSnapshot(
              name: 'Арлан',
              selectedCategory: ModelCategory.standard,
              enabledSkills: {'instructions'},
            ),
            isCurrent: false,
          ),
        ];

        await tester.pumpWidget(
          createTestApp(
            const AssistantVersionsPage(ownerId: testOwner),
            versions: versionsList,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Both versions displayed
        expect(find.byKey(const Key('version.card.2')), findsOneWidget);
        expect(find.byKey(const Key('version.card.1')), findsOneWidget);
        expect(find.text('Текущая'), findsOneWidget);

        // Tap on version 1 to trigger rollback dialog
        await tester.tap(find.byKey(const Key('version.card.1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // D04 sheet is visible with pre-summary
        expect(find.text('Восстановить версию 1?'), findsOneWidget);
        expect(find.text('Что изменится:'), findsOneWidget);
        expect(find.text('Что сохранится:'), findsOneWidget);

        // Tap confirm rollback
        await tester.tap(find.byKey(const Key('rollback.confirmBtn')));
        await tester.pump();
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 500));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Configuration rolled back to name "Арлан"
        final config = await tester.runAsync(
          () => repo.getConfiguration(testOwner),
        );
        expect(config?.name, equals('Арлан'));
      },
    );

    testWidgets(
      'F09-09: S15 displays local data breakdown and retention segments',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(const LocalDataSettingsPage(ownerId: testOwner)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Локальное хранилище'), findsOneWidget);
        expect(find.text('Карта сохранённых данных'), findsOneWidget);
        expect(
          find.byKey(const Key('localData.retentionSegments')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('localData.resetBtn')), findsOneWidget);
      },
    );

    testWidgets(
      'F09-10 & F09-V02: D05 requires typing "СБРОС" to enable reset confirmation',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    showResetConfirmationDialog(context, ownerId: testOwner),
                child: const Text('Открыть сброс'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Открыть сброс'));
        await tester.pumpAndSettle();

        expect(find.text('Сбросить ассистента?'), findsOneWidget);
        expect(find.text('Будет удалено:'), findsOneWidget);

        // Confirm button is disabled before typing word
        var confirmBtn = tester.widget<TextButton>(
          find.descendant(
            of: find.byKey(const Key('reset.confirmBtn')),
            matching: find.byType(TextButton),
          ),
        );
        expect(confirmBtn.onPressed, isNull);

        // Enter wrong word
        final field = find.byKey(const Key('reset.confirmationWordField'));
        await tester.enterText(field, 'НЕ ТО');
        await tester.pumpAndSettle();

        confirmBtn = tester.widget<TextButton>(
          find.descendant(
            of: find.byKey(const Key('reset.confirmBtn')),
            matching: find.byType(TextButton),
          ),
        );
        expect(confirmBtn.onPressed, isNull);

        // Enter correct word "СБРОС"
        await tester.enterText(field, 'СБРОС');
        await tester.pumpAndSettle();

        confirmBtn = tester.widget<TextButton>(
          find.descendant(
            of: find.byKey(const Key('reset.confirmBtn')),
            matching: find.byType(TextButton),
          ),
        );
        expect(confirmBtn.onPressed, isNotNull);
      },
    );

    testWidgets(
      'AssistantPage renders Level 0 baseline state when no levels are completed',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            const AssistantPage(ownerId: testOwner),
            completedLevels: const {},
          ),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Готов к первым задачам'), findsOneWidget);
        expect(find.byType(AppBar), findsNothing);
        expect(
          find.byKey(const Key('assistant.resumeLessonBanner')),
          findsNothing,
        );
        expect(find.byKey(const Key('assistant.character')), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(const Key('assistant.character'))).dy,
          lessThan(
            tester.getTopLeft(find.byKey(const Key('assistant.stateTitle'))).dy,
          ),
        );
        expect(find.byKey(const Key('assistant.newChatFab')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('assistant.historyBtn')),
          200,
        );
        expect(find.byKey(const Key('assistant.historyBtn')), findsOneWidget);
        expect(find.byKey(const Key('assistant.settingsBtn')), findsOneWidget);
        expect(find.byKey(const Key('assistant.newChatFab')), findsOneWidget);
      },
    );

    testWidgets(
      'AssistantPage renders Level 1 state when Level 1 is completed',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            const AssistantPage(ownerId: testOwner),
            completedLevels: const {1},
          ),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Учитывает ваши настройки'), findsOneWidget);
        expect(
          find.byKey(const Key('assistant.stateDescription')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'AssistantPage renders Level 3 state when Levels 1, 2, 3 are completed',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            const AssistantPage(ownerId: testOwner),
            completedLevels: const {1, 2, 3},
          ),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Работает с вашими материалами'), findsOneWidget);
        expect(
          find.byKey(const Key('assistant.stateDescription')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'AssistantPage renders course completed state when all 5 levels are completed',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            const AssistantPage(ownerId: testOwner),
            completedLevels: const {1, 2, 3, 4, 5},
          ),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Помогает переходить к действиям'), findsOneWidget);
        expect(
          find.byKey(const Key('assistant.stateDescription')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
