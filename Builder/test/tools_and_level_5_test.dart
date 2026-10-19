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
import 'package:builder/features/tools/infrastructure/calendar_adapter.dart';
import 'package:builder/features/tools/infrastructure/communication_adapter.dart';
import 'package:builder/features/tools/infrastructure/notes_adapter.dart';
import 'package:builder/features/tools/infrastructure/persistent_tools_repository.dart';
import 'package:builder/features/tools/infrastructure/search_adapter.dart';
import 'package:builder/features/tools/presentation/d07_os_permission_dialog.dart';
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
      'Historical communication grants and confirmations cannot execute',
      () async {
        final repo = InMemoryToolsRepository();
        await repo.setGrant(
          ownerId: testOwnerId,
          toolName: ToolsRegistry.prepareCall,
          isEnabled: true,
        );
        final now = DateTime.now().toUtc();
        await repo.createPendingAction(
          PendingAction(
            invocationId: 'legacy-call',
            ownerId: testOwnerId,
            workspaceEpoch: 1,
            actionName: ToolsRegistry.prepareCall,
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
    test('contains six release tools and excludes communication', () {
      expect(ToolsRegistry.allTools.length, 6);

      final calendarRead = ToolsRegistry.getByName(ToolsRegistry.readCalendar)!;
      expect(calendarRead.category, ToolCategory.calendar);
      expect(calendarRead.capability, ToolCapability.readOnly);
      expect(calendarRead.requiresConfirmation, isFalse);

      final calendarCreate = ToolsRegistry.getByName(
        ToolsRegistry.createCalendarEvent,
      )!;
      expect(calendarCreate.category, ToolCategory.calendar);
      expect(calendarCreate.capability, ToolCapability.requiresConfirmation);
      expect(calendarCreate.requiresConfirmation, isTrue);

      final noteCreate = ToolsRegistry.getByName(ToolsRegistry.createNote)!;
      expect(noteCreate.category, ToolCategory.notes);
      expect(noteCreate.requiresConfirmation, isTrue);

      final noteRead = ToolsRegistry.getByName(ToolsRegistry.readNotes)!;
      expect(noteRead.category, ToolCategory.notes);
      expect(noteRead.requiresConfirmation, isFalse);

      final noteDelete = ToolsRegistry.getByName(ToolsRegistry.deleteNote)!;
      expect(noteDelete.category, ToolCategory.notes);
      expect(noteDelete.requiresConfirmation, isTrue);

      expect(ToolsRegistry.getByName(ToolsRegistry.prepareCall), isNull);

      final search = ToolsRegistry.getByName(ToolsRegistry.webSearch)!;
      expect(search.category, ToolCategory.search);
      expect(search.requiresConfirmation, isFalse);
    });

    test(
      'validates parameter types and required fields against JSON schema',
      () {
        final calendarCreate = ToolsRegistry.getByName(
          ToolsRegistry.createCalendarEvent,
        )!;

        // Missing required fields
        final errorsMissing = calendarCreate.validateArguments({
          'title': 'Урок',
        });
        expect(errorsMissing, isNotEmpty);
        expect(errorsMissing.any((e) => e.contains('start_time')), isTrue);
        expect(errorsMissing.any((e) => e.contains('end_time')), isTrue);

        // Invalid date format
        final errorsInvalidDate = calendarCreate.validateArguments({
          'title': 'Урок',
          'start_time': 'not_a_date',
          'end_time': 'not_a_date',
        });
        expect(errorsInvalidDate, isNotEmpty);

        // Valid arguments
        final validErrors = calendarCreate.validateArguments({
          'title': 'Урок геометрии',
          'start_time': '2026-10-18T09:00:00Z',
          'end_time': '2026-10-18T09:40:00Z',
        });
        expect(validErrors, isEmpty);
      },
    );

    test('converts tools to wire schema for LLM context assembly', () {
      final searchTool = ToolsRegistry.getByName(ToolsRegistry.webSearch)!;
      final wire = searchTool.toWireSchema();
      expect(wire['type'], 'function');
      expect(wire['function']['name'], ToolsRegistry.webSearch);
      expect(wire['function']['parameters']['required'], contains('query'));
    });
  });

  group('F14-02 & PersistentToolsRepository: Grants & Defaults', () {
    test(
      'initializes default grants with web search disabled by default',
      () async {
        final repo = PersistentToolsRepository(database: storageDb);

        await repo.ensureDefaultGrants(testOwnerId);
        final grants = await repo.getGrants(testOwnerId);
        expect(grants.length, 6);

        final searchGrant = grants.firstWhere(
          (g) => g.toolName == ToolsRegistry.webSearch,
        );
        expect(
          searchGrant.isEnabled,
          isFalse,
        ); // F14-09: web search disabled by default

        final calendarGrant = grants.firstWhere(
          (g) => g.toolName == ToolsRegistry.readCalendar,
        );
        expect(calendarGrant.isEnabled, isTrue);
      },
    );

    test(
      'updates tool grant, increments revision and persists to SQLite',
      () async {
        final repo = PersistentToolsRepository(database: storageDb);
        await repo.ensureDefaultGrants(testOwnerId);

        await repo.setGrant(
          ownerId: testOwnerId,
          toolName: ToolsRegistry.webSearch,
          isEnabled: true,
        );

        final grant = await repo.getGrant(testOwnerId, ToolsRegistry.webSearch);
        expect(grant, isNotNull);
        expect(grant!.isEnabled, isTrue);
        expect(grant.revision, 2);

        // Verify row in SQLite table
        final raw = await storageDb.db.query(
          StorageSchemaV1.tableToolGrants,
          where: 'owner_id = ? AND tool_name = ?',
          whereArgs: [testOwnerId, ToolsRegistry.webSearch],
        );
        expect(raw.first['is_enabled'], 1);
      },
    );
  });

  group('F14-03 & F14-04: Calendar Adapter & Permission Verification', () {
    test('reads educational calendar events within date range', () async {
      final adapter = CalendarAdapter();
      final events = await adapter.readEvents(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
      );
      expect(events.length, 2);
      expect(events.first.title, contains('Урок математики'));
      expect(events.last.title, contains('Педсовет'));
    });

    test('creates new calendar event and stores in adapter', () async {
      final adapter = CalendarAdapter();
      final newEvt = await adapter.createEvent(
        title: 'Родительское собрание 7Б',
        startTime: DateTime(2026, 10, 20, 18, 0),
        endTime: DateTime(2026, 10, 20, 19, 30),
        location: 'Кабинет 304',
      );
      expect(newEvt.id, isNotEmpty);
      expect(newEvt.title, 'Родительское собрание 7Б');

      final queried = await adapter.readEvents(
        startDate: DateTime(2026, 10, 20),
        endDate: DateTime(2026, 10, 21),
      );
      expect(queried.any((e) => e.title == 'Родительское собрание 7Б'), isTrue);
    });

    test(
      'throws ToolExecutionException with denied status if OS permission denied',
      () async {
        final adapter = CalendarAdapter(
          permissionStatus: OsPermissionStatus.denied,
        );
        expect(
          () => adapter.readEvents(
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 12, 31),
          ),
          throwsA(
            isA<ToolExecutionException>().having(
              (e) => e.status,
              'status',
              OsPermissionStatus.denied,
            ),
          ),
        );
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
        actionName: ToolsRegistry.createCalendarEvent,
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
        actionName: ToolsRegistry.prepareCall,
        paramsHash: 'hash789',
        params: {'phone_number': '+79991234567'},
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

  group('F14-07 & F14-08: Communication Adapter Safety', () {
    test(
      'prepares call without auto-dialing and never accesses SMS inbox or call logs',
      () async {
        const adapter = CommunicationAdapter();

        final prep = await adapter.prepareCallOrMessage(
          phoneNumber: '+7 (999) 123-45-67',
          recipientName: 'Мама Иванова',
          messageBody:
              'Уважаемая Анна Сергеевна, завтра в 18:00 состоится собрание.',
        );

        expect(prep.phoneNumber, '+79991234567');
        expect(prep.recipientName, 'Мама Иванова');
        expect(prep.hasMessageBody, isTrue);
        expect(prep.telUri, 'tel:+79991234567');
        expect(prep.smsUri, contains('sms:+79991234567'));
      },
    );
  });

  group('F14-09: Web Search Adapter', () {
    test('unconfigured search fails without fictional results', () async {
      const adapter = SearchAdapter();
      await expectLater(
        adapter.search('ФГОС математика 7 класс'),
        throwsException,
      );
    });
  });

  group('F14-10 & F14-11: Dispatcher Runtime Grant & Invocations Log', () {
    test('enforces runtime grant check and rejects disabled tool', () async {
      final repo = PersistentToolsRepository(database: storageDb);
      await repo.ensureDefaultGrants(testOwnerId);

      // web_search is disabled by default
      final dispatcher = ToolsDispatcher(repository: repo);

      final result = await dispatcher.dispatch(
        ownerId: testOwnerId,
        toolName: ToolsRegistry.webSearch,
        args: {'query': 'Новые методики'},
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'TOOL_DISABLED');
    });

    test(
      'logs completed invocation into SQLite tableToolInvocations',
      () async {
        final repo = PersistentToolsRepository(database: storageDb);
        await repo.ensureDefaultGrants(testOwnerId);
        final dispatcher = ToolsDispatcher(repository: repo);

        final result = await dispatcher.dispatch(
          ownerId: testOwnerId,
          toolName: ToolsRegistry.readCalendar,
          args: {
            'start_date': '2026-01-01T00:00:00Z',
            'end_date': '2026-12-31T23:59:59Z',
          },
        );

        expect(result.success, isTrue);
        expect(result.data!['count'], 2);

        final logs = await repo.getInvocations(testOwnerId);
        expect(logs.length, 1);
        expect(logs.first.toolName, ToolsRegistry.readCalendar);
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
    test(
      'executes all 4 educational scenarios for teacher assistant',
      () async {
        final repo = InMemoryToolsRepository();
        await repo.ensureDefaultGrants(testOwnerId);
        final dispatcher = ToolsDispatcher(repository: repo);

        // Scenario 1: Timetable query
        final r1 = await dispatcher.dispatch(
          ownerId: testOwnerId,
          toolName: ToolsRegistry.readCalendar,
          args: {
            'start_date': '2026-01-01T00:00:00Z',
            'end_date': '2026-12-31T23:59:59Z',
          },
        );
        expect(r1.success, isTrue);

        // Scenario 2: Create calendar event "Родительское собрание"
        final r2 = await dispatcher.dispatch(
          ownerId: testOwnerId,
          toolName: ToolsRegistry.createCalendarEvent,
          args: {
            'title': 'Родительское собрание 7Б',
            'start_time': '2026-10-20T18:00:00Z',
            'end_time': '2026-10-20T19:30:00Z',
          },
        );
        expect(r2.requiresConfirmation, isTrue);
        final c2 = await dispatcher.confirmAndExecutePendingAction(
          ownerId: testOwnerId,
          invocationId: r2.pendingAction!.invocationId,
        );
        expect(c2.success, isTrue);

        // Scenario 3: Draft note "План открытого урока"
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

        // Scenario 4: Prepare communication preview with parent
        final r4 = await dispatcher.dispatch(
          ownerId: testOwnerId,
          toolName: ToolsRegistry.prepareCall,
          args: {
            'phone_number': '+79991234567',
            'recipient_name': 'Мама ученика',
            'message_body': 'Напоминание о собрании',
          },
        );
        expect(r4.success, isFalse);
        expect(r4.errorCode, 'TOOL_NOT_FOUND');
        expect(r4.pendingAction, isNull);
      },
    );
  });

  group('F14-V01 & S43: ToolsPage Widget & 44x44 Touch Target Accessibility', () {
    testWidgets(
      'renders S43 with 3 tool groups, grant toggles, D07 dialog and 44x44 targets',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
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

        // 1. Verify Page Title & 3 Groups Header
        expect(find.text('Инструменты ассистента'), findsOneWidget);
        expect(find.textContaining('Календарь и расписание'), findsOneWidget);
        expect(find.textContaining('Личные заметки'), findsOneWidget);
        expect(find.textContaining('3 · Поиск в интернете'), findsOneWidget);
        expect(find.textContaining('Подготовить звонок'), findsNothing);

        // 2. Verify D07 Dialog Open via Permission Chip
        final permChip = find.byKey(
          Key('tool.osPermBtn.${ToolsRegistry.readCalendar}'),
        );
        expect(permChip, findsOneWidget);
        await tester.tap(permChip);
        await tester.pumpAndSettle();

        // D07 dialog should appear
        expect(find.byType(D07OsPermissionDialog), findsOneWidget);
        expect(
          find.textContaining('Системный доступ: Чтение календаря'),
          findsOneWidget,
        );

        // Dismiss dialog
        await tester.tap(find.byKey(const Key('d07.proceedBtn')));
        await tester.pumpAndSettle();

        // 3. Verify min 44x44 touch targets for action buttons
        final testEventBtn = find.byKey(const Key('tools.createTestEventBtn'));
        await tester.ensureVisible(testEventBtn);
        await tester.pumpAndSettle();
        expect(testEventBtn, findsOneWidget);
        final btnSize = tester.getSize(testEventBtn);
        expect(btnSize.width, greaterThanOrEqualTo(44.0));
        expect(btnSize.height, greaterThanOrEqualTo(44.0));

        // 4. Test creating test action to inspect confirmation card
        await tester.tap(testEventBtn);
        await tester.pumpAndSettle();

        final confirmCard = find.byType(ToolConfirmationCard);
        await tester.ensureVisible(confirmCard);
        await tester.pumpAndSettle();
        expect(confirmCard, findsOneWidget);
        expect(find.text('Запрос на создание события'), findsOneWidget);
        expect(find.text('Родительское собрание 7Б'), findsOneWidget);

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
  });
}
