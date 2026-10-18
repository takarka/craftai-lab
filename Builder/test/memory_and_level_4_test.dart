import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/features/chat/domain/context_assembler.dart';
import 'package:builder/features/memory/domain/memory_models.dart';
import 'package:builder/features/memory/infrastructure/persistent_memory_repository.dart';
import 'package:builder/features/memory/presentation/memory_page.dart';
import 'package:builder/features/memory/presentation/memory_providers.dart';
import 'package:builder/features/trace/domain/request_trace.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late StorageDatabase storageDb;
  const testOwnerId = 'teacher_f13_test';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('memory_test_');
    final dbPath = '${tempDir.path}/test_builder.db';
    storageDb = StorageDatabase(
      databasePath: dbPath,
      databaseFactory: databaseFactoryFfi,
    );
    await storageDb.open();

    // Insert workspace row for foreign key constraint
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await storageDb.db.insert(StorageSchemaV1.tableWorkspaces, {
      'owner_id': testOwnerId,
      'installation_id': 'inst_f13',
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
    'F13-01 & F13-06: Persistent Memory Repository Fact CRUD & Physical Deletion (ADR-02)',
    () {
      test(
        'adds, updates, toggles and physically deletes memory facts',
        () async {
          final repo = PersistentMemoryRepository(database: storageDb);

          // 1. Add Fact (F13-01)
          final fact1 = await repo.addFact(
            ownerId: testOwnerId,
            factText: 'В 7 «Б» классе 24 ученика',
          );
          expect(fact1.id, isNotEmpty);
          expect(fact1.factText, 'В 7 «Б» классе 24 ученика');
          expect(fact1.source, MemoryFactSource.manual);
          expect(fact1.isEnabled, isTrue);

          final factsAfterAdd = await repo.getFacts(ownerId: testOwnerId);
          expect(factsAfterAdd.length, 1);
          expect(factsAfterAdd.first.factText, 'В 7 «Б» классе 24 ученика');

          // 2. Update Fact
          final updated = await repo.updateFact(
            id: fact1.id,
            factText: 'В 7 «Б» классе 26 учеников (пришли двое новеньких)',
          );
          expect(updated.factText, contains('26 учеников'));

          final factsAfterUpdate = await repo.getFacts(ownerId: testOwnerId);
          expect(factsAfterUpdate.first.factText, contains('26 учеников'));

          // 3. Toggle Fact (Disable)
          await repo.toggleFact(id: fact1.id, isEnabled: false);
          final enabledFacts = await repo.getFacts(
            ownerId: testOwnerId,
            enabledOnly: true,
          );
          expect(enabledFacts, isEmpty);

          final allFacts = await repo.getFacts(
            ownerId: testOwnerId,
            enabledOnly: false,
          );
          expect(allFacts.first.isEnabled, isFalse);

          // 4. Physical Deletion (ADR-02)
          await repo.deleteFact(id: fact1.id, ownerId: testOwnerId);
          final factsAfterDelete = await repo.getFacts(ownerId: testOwnerId);
          expect(factsAfterDelete, isEmpty);

          // Verify row is physically deleted from SQLite table
          final rawRows = await storageDb.db.query(
            StorageSchemaV1.tableMemoryFacts,
            where: 'id = ?',
            whereArgs: [fact1.id],
          );
          expect(rawRows, isEmpty);
        },
      );
    },
  );

  group('F13-03: Model Suggested Facts Workflow (Accept / Dismiss)', () {
    test(
      'suggested facts are not in active memory until explicitly accepted',
      () async {
        final repo = PersistentMemoryRepository(database: storageDb);

        // Initially candidate fact exists
        final candidates = await repo.getSuggestedFacts(ownerId: testOwnerId);
        expect(candidates, isNotEmpty);
        final candidate = candidates.first;

        // Active facts should be empty initially
        var activeFacts = await repo.getFacts(ownerId: testOwnerId);
        expect(activeFacts, isEmpty);

        // Add a custom proposal
        final customCandidate = await repo.addSuggestedFact(
          ownerId: testOwnerId,
          factText: 'Уроки длятся 40 минут по расписанию второй смены',
          rationale: 'Упомянуто учителем в сообщении',
        );

        // Dismiss the first candidate
        await repo.dismissSuggestedFact(
          ownerId: testOwnerId,
          candidateId: candidate.id,
        );
        final candidatesAfterDismiss = await repo.getSuggestedFacts(
          ownerId: testOwnerId,
        );
        expect(
          candidatesAfterDismiss.any((c) => c.id == candidate.id),
          isFalse,
        );

        // Accept customCandidate -> saved into memory with source = suggested
        final savedFact = await repo.acceptSuggestedFact(
          ownerId: testOwnerId,
          candidateId: customCandidate.id,
        );
        expect(savedFact.factText, contains('40 минут'));
        expect(savedFact.source, MemoryFactSource.suggested);

        // Now active facts contain the saved fact
        activeFacts = await repo.getFacts(ownerId: testOwnerId);
        expect(activeFacts.length, 1);
        expect(activeFacts.first.source, MemoryFactSource.suggested);
      },
    );
  });

  group('F13-04: Deterministic Memory Selection Policy & Token Budget', () {
    test(
      'selects enabled facts in deterministic order and enforces token budget',
      () {
        final now = DateTime.now().toUtc();
        final facts = [
          MemoryFact(
            id: '1',
            ownerId: testOwnerId,
            factText: 'Первый факт: В классе 24 ученика.',
            source: MemoryFactSource.manual,
            isEnabled: true,
            createdAtUtc: now.subtract(const Duration(minutes: 10)),
            updatedAtUtc: now,
          ),
          MemoryFact(
            id: '2',
            ownerId: testOwnerId,
            factText: 'Второй факт: Отключенный факт не должен войти.',
            source: MemoryFactSource.manual,
            isEnabled: false,
            createdAtUtc: now.subtract(const Duration(minutes: 5)),
            updatedAtUtc: now,
          ),
          MemoryFact(
            id: '3',
            ownerId: testOwnerId,
            factText: 'Третий факт: Длительность урока 40 минут.',
            source: MemoryFactSource.manual,
            isEnabled: true,
            createdAtUtc: now.subtract(const Duration(minutes: 1)),
            updatedAtUtc: now,
          ),
        ];

        // Generous budget: should select enabled facts in createdAtUtc ascending order
        const normalPolicy = MemorySelectionPolicy(maxTokenBudget: 500);
        final selected = normalPolicy.selectForContext(facts);
        expect(selected.length, 2);
        expect(selected[0].id, '1');
        expect(selected[1].id, '3');

        // Constrained budget: should trim facts that exceed budget
        const tightPolicy = MemorySelectionPolicy(maxTokenBudget: 15);
        final tightSelected = tightPolicy.selectForContext(facts);
        expect(tightSelected.length, 1);
        expect(tightSelected.first.id, '1');
      },
    );
  });

  group(
    'F13-05 & F13-08: Context Assembly, Request Trace & Ephemeral History Independence',
    () {
      test(
        'ContextAssembler formats memory facts and RequestTrace includes memory layer',
        () {
          const assembler = ContextAssembler();
          final manifest = assembler.assemble(
            manifestId: 'manifest_test',
            requestId: 'req_test',
            category: 'fast',
            catalogRevision: '2026-03-31-01',
            contextWindow: 128000,
            activeInstruction: 'Ты — помощник учителя.',
            memoryFacts: [
              'В 7 «Б» классе 24 ученика',
              'Длительность урока 40 минут',
            ],
            knowledgeChunks: [],
            conversationHistory: [],
            userPrompt: 'Сколько команд по 4 человека получится?',
          );

          // Check system prompt formatting
          final systemMsg = manifest.messages.firstWhere(
            (m) => m['role'] == 'system',
          );
          expect(systemMsg['content'], contains('Факты памяти:'));
          expect(systemMsg['content'], contains('- В 7 «Б» классе 24 ученика'));
          expect(
            systemMsg['content'],
            contains('- Длительность урока 40 минут'),
          );

          // Check RequestTrace generation
          final trace = RequestTrace.fromExecution(
            requestId: 'req_test',
            conversationId: 'conv_test',
            ownerId: testOwnerId,
            modelCategory: 'fast',
            assistantVersion: 1,
            userPrompt: 'Сколько команд по 4 человека получится?',
            responseText: 'Получится 6 команд по 4 человека.',
            durationMs: 150,
            status: TraceStatus.completed,
            manifest: manifest,
          );

          final memoryLayer = trace.layers.firstWhere(
            (l) => l.type == TraceLayerType.memory,
          );
          expect(memoryLayer.title, '2 · Память');
          expect(memoryLayer.tokenCount, greaterThan(0));
          expect(memoryLayer.contentSnippet, contains('24 ученика'));
        },
      );

      test(
        'F13-08: Ephemeral conversation (no history retention) preserves memory facts',
        () {
          const assembler = ContextAssembler();

          // In ephemeral mode, conversationHistory is empty/not persisted, but memoryFacts are supplied
          final manifest = assembler.assemble(
            manifestId: 'manifest_ephemeral',
            requestId: 'req_ephemeral',
            category: 'fast',
            catalogRevision: '2026-03-31-01',
            contextWindow: 128000,
            memoryFacts: ['Профильный предмет класса — углубленная математика'],
            conversationHistory: [], // Zero history
            userPrompt: 'Какой у нас профиль?',
          );

          final systemMsg = manifest.messages.firstWhere(
            (m) => m['role'] == 'system',
          );
          expect(systemMsg['content'], contains('углубленная математика'));
          expect(manifest.messages.any((m) => m['role'] == 'user'), isTrue);
        },
      );
    },
  );

  group(
    'F13-07: Educational Practice 3-Fact Preset & Deletion Verification',
    () {
      test(
        'loads 3 educational practice presets and allows removing one',
        () async {
          final repo = PersistentMemoryRepository(database: storageDb);

          final presets = await repo.loadEducationalPracticePresets(
            ownerId: testOwnerId,
          );
          expect(presets.length, 3);
          expect(presets[0].factText, 'В 7 «Б» классе 24 ученика');
          expect(
            presets[1].factText,
            'Длительность одного урока составляет 40 минут',
          );
          expect(
            presets[2].factText,
            'Профильный предмет класса — углубленная математика',
          );

          // Verify all 3 stored in repository
          var stored = await repo.getFacts(ownerId: testOwnerId);
          expect(stored.length, 3);

          // Remove the 2nd fact (duration)
          await repo.deleteFact(id: presets[1].id, ownerId: testOwnerId);

          stored = await repo.getFacts(ownerId: testOwnerId);
          expect(stored.length, 2);
          expect(stored.any((f) => f.factText.contains('40 минут')), isFalse);
        },
      );
    },
  );

  group(
    'F13-V01 & S42: MemoryPage Widget Flow & 44x44 Touch Target Accessibility',
    () {
      testWidgets(
        'renders S42 with privacy banner, candidate card, fact cards and min 44x44 targets',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final inMemoryRepo = InMemoryMemoryRepository();
          await inMemoryRepo.addFact(
            ownerId: testOwnerId,
            factText: 'В классе 24 ученика',
          );
          await inMemoryRepo.addSuggestedFact(
            ownerId: testOwnerId,
            factText: 'Ученики сидят за 12 двухместными партами',
            rationale: 'Обнаружено в диалоге',
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                memoryRepositoryProvider.overrideWithValue(inMemoryRepo),
              ],
              child: const MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: MemoryPage(ownerId: testOwnerId),
              ),
            ),
          );

          await tester.pumpAndSettle();

          // 1. Verify Title & Privacy Banner (F13-02)
          expect(find.text('Долгая память и факты'), findsOneWidget);
          expect(find.byKey(const Key('memory.privacyBanner')), findsOneWidget);
          expect(
            find.text('Защита персональных данных учеников'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Не сохраняйте персональные данные учеников'),
            findsOneWidget,
          );

          // 2. Verify Explanation Card (F13-05)
          expect(find.text('Память vs История разговора'), findsOneWidget);

          // 3. Verify Candidate Fact with Accept / Dismiss actions (F13-03)
          expect(
            find.text('Ученики сидят за 12 двухместными партами'),
            findsOneWidget,
          );
          expect(find.text('Отклонить'), findsOneWidget);
          expect(find.text('Сохранить'), findsOneWidget);

          // 4. Verify Saved Fact Card
          expect(find.text('В классе 24 ученика'), findsOneWidget);

          // 5. Verify Min 44x44 Touch Targets for Action Buttons (F13-V01)
          final refreshBtnFinder = find.byKey(const Key('memory.refreshBtn'));
          expect(refreshBtnFinder, findsOneWidget);
          final refreshSize = tester.getSize(refreshBtnFinder);
          expect(refreshSize.width, greaterThanOrEqualTo(44.0));
          expect(refreshSize.height, greaterThanOrEqualTo(44.0));

          // 6. Test inline adding new fact
          await tester.tap(find.byKey(const Key('memory.addFactBtn')));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('memory.factInputField')),
            findsOneWidget,
          );
          await tester.enterText(
            find.byKey(const Key('memory.factInputField')),
            'Урок длится 40 минут',
          );
          await tester.tap(find.byKey(const Key('memory.saveFactBtn')));
          await tester.pumpAndSettle();

          expect(find.text('Урок длится 40 минут'), findsOneWidget);
        },
      );
    },
  );
}
