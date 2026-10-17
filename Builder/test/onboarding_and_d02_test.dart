import 'dart:async';
import 'dart:io';
import 'package:builder/app/app.dart';
import 'package:builder/app/environment/app_config.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/app/router/app_router.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/storage_providers.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/assistant/presentation/assistant_page.dart';
import 'package:builder/features/onboarding/application/onboarding_controller.dart';
import 'package:builder/features/onboarding/domain/assistant_setup.dart';
import 'package:builder/features/onboarding/infrastructure/persistent_initial_workspace_repository.dart';
import 'package:builder/features/policy/domain/policy_repository.dart';
import 'package:builder/features/policy/infrastructure/persistent_policy_repository.dart';
import 'package:builder/features/policy/policy_providers.dart';
import 'package:builder/features/session/domain/auth_tokens.dart';
import 'package:builder/features/session/infrastructure/persistent_session_repository.dart';
import 'package:builder/features/session/infrastructure/secure_token_storage.dart';
import 'package:builder/features/session/session_providers.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:builder/ui_kit/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Directory tempDir;
  late StorageDatabase database;
  late String dbPath;
  late PersistentPolicyRepository policyRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('craftai_f05_test_');
    dbPath = p.join(tempDir.path, 'f05_test.db');
    database = StorageDatabase(
      databasePath: dbPath,
      databaseFactory: databaseFactoryFfi,
    );
    await database.open();
    policyRepo = PersistentPolicyRepository(database: database);
  });

  tearDown(() async {
    if (database.isOpen) {
      await database.close();
    }
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('F05 Policy Repository (D02)', () {
    test('isPolicyAcknowledged returns false initially and true after acknowledgment', () async {
      const ownerId = 'teacher-101';
      const policyId = 'd02_cross_border_transfer';

      // 1. Initially not acknowledged
      final initial = await policyRepo.isPolicyAcknowledged(
        ownerId: ownerId,
        policyId: policyId,
      );
      expect(initial, isFalse);

      final recordBefore = await policyRepo.getAcknowledgment(
        ownerId: ownerId,
        policyId: policyId,
      );
      expect(recordBefore, isNull);

      // Workspace entry required for foreign key constraint
      await database.db.insert(StorageSchemaV1.tableWorkspaces, {
        'owner_id': ownerId,
        'installation_id': 'test-install',
        'schema_version': 1,
        'workspace_epoch': 1,
        'created_at_utc': DateTime.now().toUtc().toIso8601String(),
        'updated_at_utc': DateTime.now().toUtc().toIso8601String(),
      });

      // 2. Acknowledge policy
      await policyRepo.acknowledgePolicy(
        ownerId: ownerId,
        policyId: policyId,
        policyVersion: 'v1.0',
      );

      // 3. Now acknowledged
      final after = await policyRepo.isPolicyAcknowledged(
        ownerId: ownerId,
        policyId: policyId,
      );
      expect(after, isTrue);

      final recordAfter = await policyRepo.getAcknowledgment(
        ownerId: ownerId,
        policyId: policyId,
      );
      expect(recordAfter, isNotNull);
      expect(recordAfter!.ownerId, equals(ownerId));
      expect(recordAfter.policyId, equals(policyId));
      expect(recordAfter.policyVersion, equals('v1.0'));
      expect(recordAfter.acknowledgedAtUtc, isNotNull);
    });

    test('InMemoryPolicyRepository works independently in-memory', () async {
      final inMem = InMemoryPolicyRepository();
      expect(await inMem.isPolicyAcknowledged(ownerId: 'o1', policyId: 'p1'), isFalse);

      await inMem.acknowledgePolicy(ownerId: 'o1', policyId: 'p1', policyVersion: 'v1.0');
      expect(await inMem.isPolicyAcknowledged(ownerId: 'o1', policyId: 'p1'), isTrue);
      expect((await inMem.getAcknowledgment(ownerId: 'o1', policyId: 'p1'))!.policyVersion, equals('v1.0'));
    });
  });

  group('F05 Onboarding S01-S03 and D02 First Consent Flow', () {
    testWidgets('Full onboarding: S01 -> S02 -> S03 -> D02 "Понятно" -> S10 Assistant', (tester) async {
      const ownerId = 'teacher-owner-201';
      final inMemoryTokens = InMemorySecureTokenStorage();
      final keyStorage = InMemorySecureKeyStorage();
      final wsService = WorkspaceStorageService(
        database: database,
        keyStorage: keyStorage,
        installationId: 'test_inst',
      );
      final initialWorkspaceRepo = PersistentInitialWorkspaceRepository(
        database: database,
        installationId: 'test_inst',
      );

      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(environment: AppEnvironment.development),
          ),
          storageDatabaseProvider.overrideWithValue(database),
          workspaceStorageServiceProvider.overrideWithValue(wsService),
          persistentInitialWorkspaceRepositoryProvider.overrideWithValue(initialWorkspaceRepo),
          initialWorkspaceRepositoryProvider.overrideWithValue(initialWorkspaceRepo),
          policyRepositoryProvider.overrideWithValue(policyRepo),
          sessionRepositoryProvider.overrideWithValue(
            _TestSessionRepository(ownerId: ownerId, onboardingComplete: false),
          ),
        ],
      );
      container.read(appLocaleProvider.notifier).select(const Locale('ru'));
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const BuilderApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Starts on /onboarding (S01)
      expect(find.text('Соберите своего ассистента'), findsOneWidget);
      final nextButtonS01 = find.widgetWithText(BuilderButton, 'Начать');
      expect(nextButtonS01, findsOneWidget);
      await tester.tap(nextButtonS01);
      await tester.pumpAndSettle();

      // On /onboarding/preferences (S02)
      expect(find.text('Ваш предмет и классы'), findsOneWidget);
      // Select Mathematics
      final mathChip = find.byKey(const Key('onb.subject.mathematics'));
      expect(mathChip, findsOneWidget);
      await tester.ensureVisible(mathChip);
      await tester.tap(mathChip);
      await tester.pumpAndSettle();

      // Select grade 5
      final gradeGroup5 = find.byKey(const Key('onb.group.5'));
      expect(gradeGroup5, findsOneWidget);
      await tester.ensureVisible(gradeGroup5);
      await tester.tap(gradeGroup5);
      await tester.pumpAndSettle();

      // Tap Next to S03
      final nextButtonS02 = find.widgetWithText(BuilderButton, 'Далее');
      expect(nextButtonS02, findsOneWidget);
      await tester.ensureVisible(nextButtonS02);
      await tester.tap(nextButtonS02);
      await tester.pumpAndSettle();

      // On /onboarding/assistant (S03)
      expect(find.text('Встречайте вашего ассистента'), findsOneWidget);

      // Enter assistant name
      final nameField = find.byKey(const Key('onb.name'));
      expect(nameField, findsOneWidget);
      await tester.ensureVisible(nameField);
      await tester.enterText(nameField, 'Алгоритм');
      await tester.pumpAndSettle();

      // Tap "Создать ассистента" (onbCreate)
      final createButton = find.widgetWithText(BuilderButton, 'Создать ассистента');
      expect(createButton, findsOneWidget);
      final btnWidget = tester.widget<BuilderButton>(createButton);
      expect(btnWidget.onPressed, isNotNull);
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      // D02 bottom sheet opens on top of S03!
      expect(find.text('Запросы уходят за рубеж'), findsOneWidget);
      expect(find.text('Телефон'), findsOneWidget);
      expect(find.text('CraftAI'), findsOneWidget);
      expect(find.text('Модель'), findsOneWidget);
      expect(find.textContaining('Не отправляйте данные учеников'), findsOneWidget);

      // Tap "Понятно" (d02.understand)
      final understandBtn = find.byKey(const Key('d02.understand'));
      expect(understandBtn, findsOneWidget);
      await tester.tap(understandBtn);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      // Verified: Policy is acknowledged in DB!
      final acknowledged = await policyRepo.isPolicyAcknowledged(
        ownerId: ownerId,
        policyId: 'd02_cross_border_transfer',
      );
      expect(acknowledged, isTrue);

      // Verified: Navigated to /assistant (S10)
      expect(find.byType(AssistantPage), findsOneWidget);
      expect(find.text('Согласие на трансграничную передачу (D02): получено'), findsOneWidget);

      // Attempt cloud request succeeds directly
      final cloudBtn = find.byKey(const Key('assistant.cloudAction'));
      await tester.ensureVisible(cloudBtn);
      await tester.tap(cloudBtn);
      await tester.pumpAndSettle();

      expect(find.text('Запрос к облаку выполнен'), findsOneWidget);
    });

    testWidgets('Deferred D02 ("Не сейчас"): proceeds in local mode, prompts D02 on cloud attempt', (tester) async {
      const ownerId = 'teacher-owner-202';
      final inMemoryTokens = InMemorySecureTokenStorage();
      final keyStorage = InMemorySecureKeyStorage();
      final wsService = WorkspaceStorageService(
        database: database,
        keyStorage: keyStorage,
        installationId: 'test_inst',
      );
      final initialWorkspaceRepo = PersistentInitialWorkspaceRepository(
        database: database,
        installationId: 'test_inst',
      );

      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(environment: AppEnvironment.development),
          ),
          storageDatabaseProvider.overrideWithValue(database),
          workspaceStorageServiceProvider.overrideWithValue(wsService),
          persistentInitialWorkspaceRepositoryProvider.overrideWithValue(initialWorkspaceRepo),
          initialWorkspaceRepositoryProvider.overrideWithValue(initialWorkspaceRepo),
          policyRepositoryProvider.overrideWithValue(policyRepo),
          sessionRepositoryProvider.overrideWithValue(
            _TestSessionRepository(ownerId: ownerId, onboardingComplete: false),
          ),
        ],
      );
      container.read(appLocaleProvider.notifier).select(const Locale('ru'));
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const BuilderApp(),
        ),
      );
      await tester.pumpAndSettle();

      // S01 -> S02
      await tester.tap(find.widgetWithText(BuilderButton, 'Начать'));
      await tester.pumpAndSettle();

      // S02: pick physics and 8-9
      final physicsChip = find.byKey(const Key('onb.subject.physics'));
      await tester.ensureVisible(physicsChip);
      await tester.tap(physicsChip);
      await tester.pumpAndSettle();

      final grade8 = find.byKey(const Key('onb.group.8'));
      await tester.ensureVisible(grade8);
      await tester.tap(grade8);
      await tester.pumpAndSettle();

      // S02 -> S03
      final nextBtn = find.widgetWithText(BuilderButton, 'Далее');
      await tester.ensureVisible(nextBtn);
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      // S03: name and tap "Создать ассистента"
      final nameField = find.byKey(const Key('onb.name'));
      await tester.ensureVisible(nameField);
      await tester.enterText(nameField, 'Ньютон');
      await tester.pumpAndSettle();

      final createBtn = find.widgetWithText(BuilderButton, 'Создать ассистента');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      // D02 sheet is visible
      expect(find.text('Запросы уходят за рубеж'), findsOneWidget);

      // User taps "Не сейчас" (d02.notNow)
      final notNowBtn = find.byKey(const Key('d02.notNow'));
      expect(notNowBtn, findsOneWidget);
      await tester.ensureVisible(notNowBtn);
      await tester.tap(notNowBtn);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      // Verified: Policy is NOT acknowledged in DB
      final acknowledged = await policyRepo.isPolicyAcknowledged(
        ownerId: ownerId,
        policyId: 'd02_cross_border_transfer',
      );
      expect(acknowledged, isFalse);

      // Navigated to /assistant in local mode!
      expect(find.byType(AssistantPage), findsOneWidget);
      expect(find.text('Режим без облака: согласие D02 отложено'), findsOneWidget);

      // Now user attempts cloud request in /assistant -> D02 prompts again!
      final cloudBtn = find.byKey(const Key('assistant.cloudAction'));
      await tester.ensureVisible(cloudBtn);
      await tester.tap(cloudBtn);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      expect(find.text('Запросы уходят за рубеж'), findsOneWidget);

      // User confirms this time
      await tester.tap(find.byKey(const Key('d02.understand')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      // Now policy is acknowledged
      expect(
        await policyRepo.isPolicyAcknowledged(
          ownerId: ownerId,
          policyId: 'd02_cross_border_transfer',
        ),
        isTrue,
      );
      expect(find.text('Согласие на трансграничную передачу (D02): получено'), findsOneWidget);
      expect(find.text('Запрос к облаку разрешён (согласие получено)'), findsOneWidget);
    });
  });
}

class _TestSessionRepository implements SessionRepository {
  _TestSessionRepository({
    required this.ownerId,
    required this.onboardingComplete,
  });

  final String ownerId;
  final bool onboardingComplete;
  final _controller = StreamController<SessionSnapshot>.broadcast();

  @override
  Stream<SessionSnapshot> watchSession() async* {
    yield AuthenticatedSession(
      ownerId: ownerId,
      onboardingComplete: onboardingComplete,
    );
    yield* _controller.stream;
  }
}
