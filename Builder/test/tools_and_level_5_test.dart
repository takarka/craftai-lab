import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/ui_kit/ui_kit.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/features/tools/domain/pending_action.dart';
import 'package:builder/features/tools/domain/tool_definition.dart';
import 'package:builder/features/tools/domain/tools_dispatcher.dart';
import 'package:builder/features/tools/domain/tools_registry.dart';
import 'package:builder/features/tools/infrastructure/notes_adapter.dart';
import 'package:builder/features/tools/infrastructure/persistent_tools_repository.dart';
import 'package:builder/features/tools/presentation/tool_confirmation_card.dart';
import 'package:builder/features/tools/presentation/tools_page.dart';
import 'package:builder/features/tools/presentation/tools_providers.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late StorageDatabase storageDb;
  const testOwnerId = 'teacher_f14_test';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tools_test_');
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
      'installation_id': 'inst_f14',
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

  group('F14-01: Tool Registry & Schema Validation', () {
    test(
      'Historical removed tool grants and confirmations cannot execute',
      () async {
        final repo = InMemoryToolsRepository();
        await repo.setGrant(
          ownerId: testOwnerId,
          toolName: 'prepare_call',
          isEnabled: true,
        );
        final now = DateTime.now().toUtc();
        await repo.createPendingAction(
          PendingAction(
            invocationId: 'legacy-call',
            ownerId: testOwnerId,
            workspaceEpoch: 1,
            actionName: 'prepare_call',
            paramsHash: PendingAction.computeParamsHash({
              'phone_number': '+70000000000',
            }),
            params: const {'phone_number': '+70000000000'},
            createdAtUtc: now,
            expiresAtUtc: now.add(const Duration(minutes: 5)),
          ),
        );
        final dispatcher = ToolsDispatcher(repository: repo);
        final result = await dispatcher.confirmAndExecutePendingAction(
          ownerId: testOwnerId,
          invocationId: 'legacy-call',
        );
        expect(result.success, isFalse);
        expect(result.errorCode, 'TOOL_NOT_FOUND');
        expect(
          (await repo.getPendingAction('legacy-call'))!.status,
          PendingActionStatus.pending,
        );
        expect(await repo.getInvocations(testOwnerId), isEmpty);
        final container = ProviderContainer(
          overrides: [toolsRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);
        container.read(toolsControllerProvider(testOwnerId));
        await container
            .read(toolsControllerProvider(testOwnerId).notifier)
            .load();
        expect(
          container.read(toolsControllerProvider(testOwnerId)).pendingActions,
          isEmpty,
        );
      },
    );
    test('contains three notes tools in MVP registry', () {
      expect(ToolsRegistry.allTools.length, 3);

      final noteCreate = ToolsRegistry.getByName(ToolsRegistry.createNote)!;
      expect(noteCreate.category, ToolCategory.notes);
      expect(noteCreate.capability, ToolCapability.requiresConfirmation);
      expect(noteCreate.requiresConfirmation, isTrue);

      final noteRead = ToolsRegistry.getByName(ToolsRegistry.readNotes)!;
      expect(noteRead.category, ToolCategory.notes);
      expect(noteRead.capability, ToolCapability.readOnly);
      expect(noteRead.requiresConfirmation, isFalse);

      final noteDelete = ToolsRegistry.getByName(ToolsRegistry.deleteNote)!;
      expect(noteDelete.category, ToolCategory.notes);
      expect(noteDelete.capability, ToolCapability.requiresConfirmation);
      expect(noteDelete.requiresConfirmation, isTrue);

      expect(ToolsRegistry.getByName('prepare_call'), isNull);
    });

    test(
      'validates parameter types and required fields against JSON schema',
      () {
        final noteCreate = ToolsRegistry.getByName(ToolsRegistry.createNote)!;

        // Missing required fields
        final errorsMissing = noteCreate.validateArguments({'title': 'Урок'});
        expect(errorsMissing, isNotEmpty);
        expect(errorsMissing.any((e) => e.contains('content')), isTrue);

        // Valid arguments
        final validErrors = noteCreate.validateArguments({
          'title': 'Урок геометрии',
          'content': 'План урока',
        });
        expect(validErrors, isEmpty);
      },
    );

    test('converts tools to wire schema for LLM context assembly', () {
      final noteTool = ToolsRegistry.getByName(ToolsRegistry.createNote)!;
      final wire = noteTool.toWireSchema();
      expect(wire['type'], 'function');
      expect(wire['function']['name'], ToolsRegistry.createNote);
      expect(wire['function']['parameters']['required'], contains('title'));
    });
  });

  group('F14-02 & PersistentToolsRepository: Grants & Defaults', () {
    test(
      'initializes default grants for all notes tools enabled by default',
      () async {
        final repo = PersistentToolsRepository(database: storageDb);

        await repo.ensureDefaultGrants(testOwnerId);
        final grants = await repo.getGrants(testOwnerId);
        expect(grants.length, 3);
        expect(grants.every((g) => g.isEnabled), isTrue);
      },
    );

    test(
      'updates tool grant, increments revision and persists to SQLite',
      () async {
        final repo = PersistentToolsRepository(database: storageDb);
        await repo.ensureDefaultGrants(testOwnerId);

        await repo.setGrant(
          ownerId: testOwnerId,
          toolName: ToolsRegistry.createNote,
          isEnabled: false,
        );

        final grant = await repo.getGrant(
          testOwnerId,
          ToolsRegistry.createNote,
        );
        expect(grant, isNotNull);
        expect(grant!.isEnabled, isFalse);
        expect(grant.revision, 2);

        // Verify row in SQLite table
        final raw = await storageDb.db.query(
          StorageSchemaV1.tableToolGrants,
          where: 'owner_id = ? AND tool_name = ?',
          whereArgs: [testOwnerId, ToolsRegistry.createNote],
        );
        expect(raw.first['is_enabled'], 0);
      },
    );
  });

  group('F14-05 & F14-12: PendingAction State Machine & Deterministic Hash', () {
    test(
      'computes deterministic SHA-256 hash irrespective of JSON key order',
      () {
        final mapA = {
          'title': 'Собрание',
          'start_time': '2026-10-20T18:00:00Z',
        };
        final mapB = {
          'start_time': '2026-10-20T18:00:00Z',
          'title': 'Собрание',
        };

        final hashA = PendingAction.computeParamsHash(mapA);
        final hashB = PendingAction.computeParamsHash(mapB);

        expect(hashA, equals(hashB));
        expect(hashA.length, 64);
      },
    );

    test('executes state transitions: pending -> approved -> executed', () {
      const sm = PendingActionStateMachine();
      final now = DateTime.now().toUtc();
      final action = PendingAction(
        invocationId: 'act_100',
        ownerId: testOwnerId,
        workspaceEpoch: 1,
        actionName: ToolsRegistry.createNote,
        paramsHash: 'hash123',
        params: {'title': 'Консультация'},
        status: PendingActionStatus.pending,
        expiresAtUtc: now.add(const Duration(minutes: 10)),
        createdAtUtc: now,
      );

      final approved = sm.approve(action);
      expect(approved.status, PendingActionStatus.approved);

      final executed = sm.markExecuted(approved);
      expect(executed.status, PendingActionStatus.executed);

      // Attempting to execute again throws StateError (Double execution guard F14-12)
      expect(() => sm.markExecuted(executed), throwsStateError);
      expect(() => sm.approve(executed), throwsStateError);
    });

    test('rejects pending action and prevents subsequent approval', () {
      const sm = PendingActionStateMachine();
      final now = DateTime.now().toUtc();
      final action = PendingAction(
        invocationId: 'act_200',
        ownerId: testOwnerId,
        workspaceEpoch: 1,
        actionName: ToolsRegistry.deleteNote,
        paramsHash: 'hash456',
        params: {'note_id': 'note_1'},
        status: PendingActionStatus.pending,
        expiresAtUtc: now.add(const Duration(minutes: 10)),
        createdAtUtc: now,
      );

      final rejected = sm.reject(action);
      expect(rejected.status, PendingActionStatus.rejected);

      expect(() => sm.approve(rejected), throwsStateError);
    });

    test('throws StateError when approving expired action', () {
      const sm = PendingActionStateMachine();
      final past = DateTime.now().toUtc().subtract(const Duration(minutes: 20));
      final action = PendingAction(
        invocationId: 'act_300',
        ownerId: testOwnerId,
        workspaceEpoch: 1,
        actionName: ToolsRegistry.deleteNote,
        paramsHash: 'hash789',
        params: {'note_id': 'note_300'},
        status: PendingActionStatus.pending,
        expiresAtUtc: past, // Expired
        createdAtUtc: past.subtract(const Duration(minutes: 10)),
      );

      expect(() => sm.approve(action), throwsStateError);
    });
  });

  group('F14-06: Notes Adapter Storage & Path Sanitization', () {
    test(
      'stores notes in isolated owner workspace directory and allows CRUD',
      () async {
        final notesDir = Directory('${tempDir.path}/notes_storage');
        final adapter = NotesAdapter(rootDirectory: notesDir);

        // Create Note
        final note1 = await adapter.createNote(
          ownerId: testOwnerId,
          title: 'План открытого урока',
          content:
              '1. Организационный момент (2 мин)\n2. Актуализация знаний (8 мин)',
        );
        expect(note1.id, isNotEmpty);
        expect(note1.title, 'План открытого урока');

        // List notes
        final list = await adapter.listNotes(testOwnerId);
        expect(list.length, 1);
        expect(list.first.title, 'План открытого урока');

        // Search notes
        final hits = await adapter.listNotes(testOwnerId, query: 'открытого');
        expect(hits.length, 1);

        final noHits = await adapter.listNotes(
          testOwnerId,
          query: 'несуществующий',
        );
        expect(noHits, isEmpty);

        // Delete note
        final deleted = await adapter.deleteNote(
          ownerId: testOwnerId,
          noteId: note1.id,
        );
        expect(deleted, isTrue);

        final listAfterDelete = await adapter.listNotes(testOwnerId);
        expect(listAfterDelete, isEmpty);
      },
    );

    test('enforces 100 KB payload limit on note creation', () async {
      final notesDir = Directory('${tempDir.path}/notes_storage_limit');
      final adapter = NotesAdapter(rootDirectory: notesDir);

      final hugeContent = 'A' * (101 * 1024); // 101 KB
      expect(
        () => adapter.createNote(
          ownerId: testOwnerId,
          title: 'Большая заметка',
          content: hugeContent,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('100 КБ'),
          ),
        ),
      );
    });

    test('sanitizes note id against path traversal', () async {
      final notesDir = Directory('${tempDir.path}/notes_storage_sec');
      final adapter = NotesAdapter(rootDirectory: notesDir);

      final note = await adapter.getNote(
        ownerId: testOwnerId,
        noteId: '../../../system_file',
      );
      expect(note, isNull);
    });
  });

  group('F14-10 & F14-11: Dispatcher Runtime Grant & Invocations Log', () {
    test('enforces runtime grant check and rejects disabled tool', () async {
      final repo = PersistentToolsRepository(database: storageDb);
      await repo.ensureDefaultGrants(testOwnerId);
      await repo.setGrant(
        ownerId: testOwnerId,
        toolName: ToolsRegistry.readNotes,
        isEnabled: false,
      );

      final dispatcher = ToolsDispatcher(repository: repo);

      final result = await dispatcher.dispatch(
        ownerId: testOwnerId,
        toolName: ToolsRegistry.readNotes,
        args: {},
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'TOOL_DISABLED');
    });

    test(
      'logs completed invocation into SQLite tableToolInvocations',
      () async {
        final repo = PersistentToolsRepository(database: storageDb);
        await repo.ensureDefaultGrants(testOwnerId);
        final dispatcher = ToolsDispatcher(
          repository: repo,
          notesAdapter: NotesAdapter(rootDirectory: tempDir),
        );

        final result = await dispatcher.dispatch(
          ownerId: testOwnerId,
          toolName: ToolsRegistry.readNotes,
          args: {},
        );

        expect(result.success, isTrue);

        final logs = await repo.getInvocations(testOwnerId);
        expect(logs.length, 1);
        expect(logs.first.toolName, ToolsRegistry.readNotes);
      },
    );

    test(
      'mutating tool returns needsConfirmation and creates PendingAction',
      () async {
        final repo = PersistentToolsRepository(database: storageDb);
        await repo.ensureDefaultGrants(testOwnerId);
        final dispatcher = ToolsDispatcher(repository: repo);

        final result = await dispatcher.dispatch(
          ownerId: testOwnerId,
          toolName: ToolsRegistry.createNote,
          args: {
            'title': 'Заметка о проверке тетрадей',
            'content': 'Проверить до среды',
          },
        );

        expect(result.requiresConfirmation, isTrue);
        expect(result.pendingAction, isNotNull);
        expect(result.pendingAction!.actionName, ToolsRegistry.createNote);

        // Confirm and execute pending action
        final execResult = await dispatcher.confirmAndExecutePendingAction(
          ownerId: testOwnerId,
          invocationId: result.pendingAction!.invocationId,
        );

        expect(execResult.success, isTrue);
        expect(
          execResult.data!['created_note']['title'],
          'Заметка о проверке тетрадей',
        );

        // Attempting to execute again fails (Double execution prevention)
        final repeatResult = await dispatcher.confirmAndExecutePendingAction(
          ownerId: testOwnerId,
          invocationId: result.pendingAction!.invocationId,
        );
        expect(repeatResult.success, isFalse);
      },
    );
  });

  group('F14-13: Educational Preset Scenarios', () {
    test('executes notes educational scenario for teacher assistant', () async {
      final repo = InMemoryToolsRepository();
      await repo.ensureDefaultGrants(testOwnerId);
      final dispatcher = ToolsDispatcher(
        repository: repo,
        notesAdapter: NotesAdapter(rootDirectory: tempDir),
      );

      // Draft note "План открытого урока"
      final r3 = await dispatcher.dispatch(
        ownerId: testOwnerId,
        toolName: ToolsRegistry.createNote,
        args: {
          'title': 'План открытого урока',
          'content': 'Тема: Квадратные уравнения',
        },
      );
      expect(r3.requiresConfirmation, isTrue);
      final c3 = await dispatcher.confirmAndExecutePendingAction(
        ownerId: testOwnerId,
        invocationId: r3.pendingAction!.invocationId,
      );
      expect(c3.success, isTrue);

      // Read notes
      final rRead = await dispatcher.dispatch(
        ownerId: testOwnerId,
        toolName: ToolsRegistry.readNotes,
        args: {},
      );
      expect(rRead.success, isTrue);

      // Legacy removed tool fails with TOOL_NOT_FOUND
      final r4 = await dispatcher.dispatch(
        ownerId: testOwnerId,
        toolName: 'prepare_call',
        args: {
          'phone_number': '+79991234567',
          'recipient_name': 'Мама ученика',
          'message_body': 'Напоминание о собрании',
        },
      );
      expect(r4.success, isFalse);
      expect(r4.errorCode, 'TOOL_NOT_FOUND');
      expect(r4.pendingAction, isNull);
    });
  });

  group(
    'F14-V01 & S43: ToolsPage Widget & 44x44 Touch Target Accessibility',
    () {
      testWidgets(
        'renders S43 with notes tool group, grant toggles and 44x44 targets',
        (tester) async {
          tester.view.physicalSize = const Size(800, 2200);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final inMemoryRepo = InMemoryToolsRepository();
          await inMemoryRepo.ensureDefaultGrants(testOwnerId);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                toolsRepositoryProvider.overrideWithValue(inMemoryRepo),
              ],
              child: const MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: ToolsPage(ownerId: testOwnerId),
              ),
            ),
          );

          await tester.pumpAndSettle();

          // 1. Verify Page Title & Notes Group Header
          expect(find.text('Инструменты ассистента'), findsOneWidget);
          expect(find.textContaining('Личные заметки'), findsOneWidget);
          expect(find.textContaining('Календарь и расписание'), findsNothing);
          expect(find.textContaining('Подготовить звонок'), findsNothing);

          // 2. Verify min 44x44 touch targets for action buttons
          final testEventBtn = find.byKey(
            const Key('tools.createTestEventBtn'),
          );
          await tester.ensureVisible(testEventBtn);
          await tester.pumpAndSettle();
          expect(testEventBtn, findsOneWidget);
          final btnSize = tester.getSize(testEventBtn);
          expect(btnSize.width, greaterThanOrEqualTo(44.0));
          expect(btnSize.height, greaterThanOrEqualTo(44.0));

          // 3. Test creating test action to inspect confirmation card
          await tester.tap(testEventBtn);
          await tester.pumpAndSettle();

          final confirmCard = find.byType(ToolConfirmationCard);
          await tester.ensureVisible(confirmCard);
          await tester.pumpAndSettle();
          expect(confirmCard, findsOneWidget);
          expect(find.text('Запрос на создание заметки'), findsOneWidget);
          expect(find.text('План родительского собрания 7Б'), findsOneWidget);

          // Test double-tap protected confirm button with min 44x44 size
          final confirmBtn = find.ancestor(
            of: find.text('Подтвердить'),
            matching: find.byType(BuilderButton),
          );
          expect(confirmBtn, findsOneWidget);
          final confirmSize = tester.getSize(confirmBtn);
          expect(confirmSize.width, greaterThanOrEqualTo(44.0));
          expect(confirmSize.height, greaterThanOrEqualTo(44.0));

          await tester.tap(confirmBtn);
          await tester.pumpAndSettle();

          // Pending action should be executed and card dismissed
          expect(find.byType(ToolConfirmationCard), findsNothing);
        },
      );
    },
  );
}
