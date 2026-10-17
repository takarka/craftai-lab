import 'dart:async';
import 'dart:io';
import 'package:builder/app/app.dart';
import 'package:builder/app/environment/app_config.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/app/router/app_router.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/auth/application/auth_controller.dart';
import 'package:builder/features/auth/domain/auth_gateway.dart';
import 'package:builder/features/auth/domain/reset_password_link_validator.dart';
import 'package:builder/features/session/domain/auth_tokens.dart';
import 'package:builder/features/session/infrastructure/persistent_session_repository.dart';
import 'package:builder/features/session/infrastructure/secure_token_storage.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockTestAuthGateway implements AuthGateway {
  bool available = true;
  String? resetPasswordToken;
  String? resetPasswordNewValue;
  Completer<void>? pending;
  Object? failure;

  @override
  bool get isAvailable => available;

  @override
  AuthLegalDocuments? documentsFor(String languageCode) => null;

  @override
  Future<void> signIn({required String email, required String password}) async {}

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String termsRevision,
    required String privacyRevision,
  }) async {}

  @override
  Future<void> requestPasswordReset({required String email}) async {}

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    resetPasswordToken = token;
    resetPasswordNewValue = newPassword;
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('AuthTokens', () {
    test('serializes and deserializes correctly', () {
      final expiry = DateTime.utc(2026, 12, 31, 23, 59, 59);
      final tokens = AuthTokens(
        accessToken: 'access_123',
        refreshToken: 'refresh_456',
        tokenType: 'Bearer',
        expiresAtUtc: expiry,
      );

      final json = tokens.toJson();
      final restored = AuthTokens.fromJson(json);

      expect(restored.accessToken, equals('access_123'));
      expect(restored.refreshToken, equals('refresh_456'));
      expect(restored.tokenType, equals('Bearer'));
      expect(restored.expiresAtUtc, equals(expiry));
      expect(restored.isExpired, isFalse);
    });

    test('isExpired detects past dates accurately', () {
      final past = AuthTokens(
        accessToken: 'old_acc',
        refreshToken: 'old_ref',
        expiresAtUtc: DateTime.utc(2020, 1, 1),
      );
      expect(past.isExpired, isTrue);
    });
  });

  group('SecureTokenStorage', () {
    test('stores, reads, and clears tokens and owner session', () async {
      final storage = InMemorySecureTokenStorage();
      expect(await storage.hasStoredSession(), isFalse);

      final tokens = AuthTokens(
        accessToken: 'acc_sec',
        refreshToken: 'ref_sec',
        expiresAtUtc: DateTime.utc(2027, 1, 1),
      );

      await storage.writeSession(ownerId: 'owner_sec_1', tokens: tokens);
      expect(await storage.hasStoredSession(), isTrue);
      expect(await storage.readOwnerId(), equals('owner_sec_1'));

      final read = await storage.readTokens();
      expect(read, isNotNull);
      expect(read!.accessToken, equals('acc_sec'));
      expect(read.refreshToken, equals('ref_sec'));

      await storage.clearSession();
      expect(await storage.hasStoredSession(), isFalse);
      expect(await storage.readOwnerId(), isNull);
      expect(await storage.readTokens(), isNull);
    });
  });

  group('ResetPasswordLinkValidator', () {
    const validator = ResetPasswordLinkValidator();

    test('accepts valid https link with token', () {
      final uri = Uri.parse(
        'https://craftai.kz/reset-password?token=secure_token_1234567890_valid',
      );
      final result = validator.validate(uri);
      expect(result, isA<ValidResetToken>());
      expect(
        (result as ValidResetToken).token,
        equals('secure_token_1234567890_valid'),
      );
    });

    test('rejects disallowed scheme', () {
      final uri = Uri.parse(
        'http://craftai.kz/reset-password?token=secure_token_1234567890_valid',
      );
      final result = validator.validate(uri);
      expect(result, isA<InvalidResetLink>());
      expect((result as InvalidResetLink).reason, contains('схема'));
    });

    test('rejects untrusted host', () {
      final uri = Uri.parse(
        'https://phishing-craftai.org/reset-password?token=secure_token_1234567890_valid',
      );
      final result = validator.validate(uri);
      expect(result, isA<InvalidResetLink>());
      expect((result as InvalidResetLink).reason, contains('узел'));
    });

    test('rejects missing or malformed token', () {
      final noToken = Uri.parse('https://craftai.kz/reset-password');
      expect(validator.validate(noToken), isA<InvalidResetLink>());

      final shortToken = Uri.parse('https://craftai.kz/reset-password?token=short');
      expect(validator.validate(shortToken), isA<InvalidResetLink>());
    });
  });

  group('PersistentSessionRepository', () {
    late Directory tempDir;
    late StorageDatabase storageDb;
    late WorkspaceStorageService workspaceService;
    late InMemorySecureTokenStorage tokenStorage;
    late PersistentSessionRepository sessionRepo;

    var refreshCallsCount = 0;

    setUp(() async {
      refreshCallsCount = 0;
      tempDir = await Directory.systemTemp.createTemp('session_repo_test_');
      final dbPath = p.join(tempDir.path, 'session_test.db');
      storageDb = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await storageDb.open();

      workspaceService = WorkspaceStorageService(
        database: storageDb,
        keyStorage: InMemorySecureKeyStorage(),
        installationId: 'test_inst',
      );

      tokenStorage = InMemorySecureTokenStorage();

      sessionRepo = PersistentSessionRepository(
        tokenStorage: tokenStorage,
        database: storageDb,
        workspaceStorageService: workspaceService,
        tokenRefresher: (oldRef) async {
          refreshCallsCount++;
          await Future.delayed(const Duration(milliseconds: 20));
          return AuthTokens(
            accessToken: 'refreshed_access_$refreshCallsCount',
            refreshToken: 'refreshed_ref_$refreshCallsCount',
            expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
          );
        },
      );
    });

    tearDown(() async {
      await sessionRepo.dispose();
      await storageDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'watchSession restores the saved account without an explicit restore call',
      () async {
        await tokenStorage.writeSession(
          ownerId: 'remembered_teacher',
          tokens: AuthTokens(
            accessToken: 'saved_access',
            refreshToken: 'saved_refresh',
            expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
        );

        final events = StreamIterator(sessionRepo.watchSession());
        expect(await events.moveNext(), isTrue);
        expect(events.current, isA<AuthenticatedSession>());
        expect(
          (events.current as AuthenticatedSession).ownerId,
          'remembered_teacher',
        );
        expect(workspaceService.activeOwnerId, 'remembered_teacher');

        await sessionRepo.signOut();
        expect(await events.moveNext(), isTrue);
        expect(events.current, isA<SignedOut>());
        await events.cancel();
        expect(await sessionRepo.watchSession().first, isA<SignedOut>());
      },
    );

    test('restoreSession emits SignedOut when no token stored', () async {
      final snapshot = await sessionRepo.restoreSession();
      expect(snapshot, isA<SignedOut>());
      expect(sessionRepo.currentSnapshot, isA<SignedOut>());
    });

    test('saves session, opens workspace, and determines onboarding complete status', () async {
      final tokens = AuthTokens(
        accessToken: 'acc_1',
        refreshToken: 'ref_1',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      // 1. Initial login: no assistant in DB yet -> onboardingComplete == false
      await sessionRepo.saveSession(ownerId: 'teacher_10', tokens: tokens);
      expect(sessionRepo.currentSnapshot, isA<AuthenticatedSession>());
      final s1 = sessionRepo.currentSnapshot as AuthenticatedSession;
      expect(s1.ownerId, equals('teacher_10'));
      expect(s1.onboardingComplete, isFalse);
      expect(workspaceService.activeOwnerId, equals('teacher_10'));

      // 2. Insert assistant configuration in DB
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      await storageDb.db.insert(StorageSchemaV1.tableAssistantConfigurations, {
        'owner_id': 'teacher_10',
        'name': 'Бот Учителя',
        'enabled_skills_json': '[]',
        'system_rules_json': '[]',
        'state_revision': 1,
        'updated_at_utc': nowUtc,
      });

      // 3. Restart app: restoreSession should find assistant and set onboardingComplete == true
      final s2 = await sessionRepo.restoreSession();
      expect(s2, isA<AuthenticatedSession>());
      expect((s2 as AuthenticatedSession).onboardingComplete, isTrue);
    });

    test('single-flight refresh prevents concurrent duplicate token refresh calls', () async {
      await tokenStorage.writeSession(
        ownerId: 'teacher_refresh',
        tokens: AuthTokens(
          accessToken: 'expired_acc',
          refreshToken: 'valid_refresh',
          expiresAtUtc: DateTime.utc(2020, 1, 1),
        ),
      );

      // Trigger 3 concurrent refreshes
      final futures = await Future.wait([
        sessionRepo.refreshTokens(),
        sessionRepo.refreshTokens(),
        sessionRepo.refreshTokens(),
      ]);

      expect(refreshCallsCount, equals(1));
      expect(futures[0].accessToken, equals(futures[1].accessToken));
      expect(futures[1].accessToken, equals(futures[2].accessToken));
    });

    test('signOut wipes memory, closes active workspace and clears token storage', () async {
      await sessionRepo.saveSession(
        ownerId: 'teacher_logout',
        tokens: AuthTokens(
          accessToken: 'acc_out',
          refreshToken: 'ref_out',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      expect(sessionRepo.currentSnapshot, isA<AuthenticatedSession>());
      expect(workspaceService.hasActiveWorkspace, isTrue);

      await sessionRepo.signOut();

      expect(sessionRepo.currentSnapshot, isA<SignedOut>());
      expect(workspaceService.hasActiveWorkspace, isFalse);
      expect(await tokenStorage.hasStoredSession(), isFalse);
    });
  });

  group('Password Reset Route & Form UI', () {
    testWidgets('renders reset password form with valid token and submits new password', (tester) async {
      final mockGateway = MockTestAuthGateway();
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(environment: AppEnvironment.development),
          ),
          authGatewayProvider.overrideWithValue(mockGateway),
          sessionRepositoryProvider.overrideWithValue(
            const NotConnectedSessionRepository(),
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

      container
          .read(appRouterProvider)
          .go('/reset-password?token=valid_test_token_123456');
      await tester.pumpAndSettle();

      // Form header and password inputs must be present
      expect(find.byKey(const Key('auth.password')), findsOneWidget);
      expect(find.byKey(const Key('auth.confirmPassword')), findsOneWidget);

      // Enter matching passwords
      await tester.enterText(find.byKey(const Key('auth.password')), 'SuperSecretPassword123');
      await tester.enterText(find.byKey(const Key('auth.confirmPassword')), 'SuperSecretPassword123');
      await tester.pump();

      // Tap submit button
      final submitButton = find.text('Сохранить пароль');
      expect(submitButton, findsOneWidget);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(mockGateway.resetPasswordToken, equals('valid_test_token_123456'));
      expect(mockGateway.resetPasswordNewValue, equals('SuperSecretPassword123'));

      // Success message displayed
      expect(find.text('Пароль успешно изменён. Теперь вы можете войти.'), findsOneWidget);
      expect(find.text('Вернуться ко входу'), findsOneWidget);
    });

    testWidgets('shows invalid link message when reset-password is opened without a token', (tester) async {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(environment: AppEnvironment.development),
          ),
          sessionRepositoryProvider.overrideWithValue(
            const NotConnectedSessionRepository(),
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

      container.read(appRouterProvider).go('/reset-password');
      await tester.pumpAndSettle();

      expect(
        find.text('Ссылка для смены пароля недействительна или устарела. Запросите новую ссылку.'),
        findsOneWidget,
      );
      expect(find.text('Вернуться ко входу'), findsOneWidget);
    });
  });
}
