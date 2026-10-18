import 'dart:async';
import 'dart:io';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/onboarding/domain/assistant_setup.dart';
import 'package:builder/features/onboarding/domain/initial_workspace_repository.dart';
import 'package:builder/features/onboarding/infrastructure/persistent_initial_workspace_repository.dart';
import 'package:builder/features/profile/domain/profile.dart';
import 'package:builder/features/profile/infrastructure/profile_store.dart';
import 'package:builder/features/profile/presentation/profile_pages.dart';
import 'package:builder/features/profile/profile_providers.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:builder/ui_kit/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _AccountGateway implements ProfileAccountGateway {
  _AccountGateway(this.action);
  final Future<AccountSnapshot> Function(String) action;
  @override
  bool get isAvailable => true;
  @override
  Future<AccountSnapshot> load(String ownerId) => action(ownerId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory temporary;
  late StorageDatabase db;
  late WorkspaceStorageService workspace;
  late ProfileStore store;
  final setup = AssistantSetup(
    subject: SchoolSubject.physics,
    grades: {7, 8},
    language: AssistantLanguage.kazakh,
    name: 'Тест',
  );
  WorkspaceWritePermit permit(String ownerId) =>
      WorkspaceWritePermit(ownerId: ownerId, canCommit: () => true);

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('builder_profile_');
    db = StorageDatabase(
      databasePath: '${temporary.path}/profile.db',
      databaseFactory: databaseFactoryFfi,
    );
    await db.open();
    workspace = WorkspaceStorageService(
      database: db,
      keyStorage: InMemorySecureKeyStorage(),
      installationId: 'test',
    );
    await workspace.openWorkspace(ownerId: 'teacher');
    final initial = PersistentInitialWorkspaceRepository(
      database: db,
      installationId: 'test',
    );
    await initial.createIfAbsent(permit: permit('teacher'), setup: setup);
    await initial.createIfAbsent(permit: permit('other'), setup: setup);
    store = ProfileStore(database: db, workspace: workspace);
  });
  tearDown(() async {
    await db.close();
    await temporary.delete(recursive: true);
  });

  test(
    'preferences survive reopening and preserve assistant language and other owners',
    () async {
      await store.savePreferences(
        permit: permit('teacher'),
        setup: setup.copyWith(
          subject: SchoolSubject.mathematics,
          grades: {5, 6},
        ),
        uiLanguage: 'kk',
      );
      await db.close();
      await db.open();
      final saved = await store.readPreferences('teacher');
      expect(saved!.setup.subject, SchoolSubject.mathematics);
      expect(saved.setup.grades, {5, 6});
      expect(saved.setup.language, AssistantLanguage.kazakh);
      expect(saved.uiLanguage, 'kk');
      expect(
        (await store.readPreferences('other'))!.setup.subject,
        SchoolSubject.physics,
      );
      final versions = await db.db.query(
        StorageSchemaV1.tableAssistantVersions,
        where: 'owner_id = ?',
        whereArgs: ['teacher'],
      );
      expect(versions.length, 1);
    },
  );

  test(
    'revoked permit and switched workspace cannot save preferences',
    () async {
      await expectLater(
        store.savePreferences(
          permit: WorkspaceWritePermit(
            ownerId: 'teacher',
            canCommit: () => false,
          ),
          setup: setup,
          uiLanguage: 'kk',
        ),
        throwsStateError,
      );
      await workspace.openWorkspace(ownerId: 'other');
      await expectLater(
        store.savePreferences(
          permit: permit('teacher'),
          setup: setup,
          uiLanguage: 'kk',
        ),
        throwsStateError,
      );
      expect((await store.readPreferences('teacher'))!.uiLanguage, 'ru');
    },
  );

  test(
    'unknown usage and absent limits round-trip without fabricated zeros',
    () async {
      final snapshot = AccountSnapshot(
        ownerId: 'teacher',
        updatedAtUtc: DateTime.utc(2026, 10, 18),
      );
      await store.saveSnapshot(snapshot, permit('teacher'));
      await db.close();
      final cached = await store.readSnapshot('teacher');
      expect(cached!.usedTokens, isNull);
      expect(cached.tokenLimit, isNull);
      expect(cached.updatedAtUtc, snapshot.updatedAtUtc);
      expect(await store.readSnapshot('other'), isNull);
    },
  );

  test(
    'account provider retains timestamped cache when refresh fails',
    () async {
      final snapshot = AccountSnapshot(
        ownerId: 'teacher',
        name: 'Teacher',
        usedTokens: 321,
        updatedAtUtc: DateTime.utc(2026, 10, 18),
      );
      await store.saveSnapshot(snapshot, permit('teacher'));
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWithValue(
            AsyncData(
              AuthenticatedSession(
                ownerId: 'teacher',
                onboardingComplete: true,
              ),
            ),
          ),
          profileStoreProvider.overrideWithValue(store),
          profileAccountGatewayProvider.overrideWithValue(
            _AccountGateway((_) async => throw StateError('offline')),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.future);
      final done = Completer<ProfileAccountState>();
      final subscription = container.listen(profileAccountProvider('teacher'), (
        _,
        next,
      ) {
        final state = next.asData?.value;
        if (state != null && state.unavailable && !done.isCompleted) {
          done.complete(state);
        }
      }, fireImmediately: true);
      addTearDown(subscription.close);
      final result = await done.future;
      expect(result.cached, isTrue);
      expect(result.snapshot!.usedTokens, 321);
      expect(result.snapshot!.updatedAtUtc, snapshot.updatedAtUtc);
    },
  );

  test('account provider rejects a response for a different owner', () async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(
          AsyncData(
            AuthenticatedSession(ownerId: 'teacher', onboardingComplete: true),
          ),
        ),
        profileStoreProvider.overrideWithValue(store),
        profileAccountGatewayProvider.overrideWithValue(
          _AccountGateway(
            (_) async => AccountSnapshot(
              ownerId: 'other',
              name: 'Wrong account',
              updatedAtUtc: DateTime.now().toUtc(),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.future);
    final done = Completer<ProfileAccountState>();
    final sub = container.listen(profileAccountProvider('teacher'), (_, next) {
      final state = next.asData?.value;
      if (state?.unavailable == true && !done.isCompleted) done.complete(state);
    }, fireImmediately: true);
    addTearDown(sub.close);
    expect((await done.future).snapshot, isNull);
    expect(await store.readSnapshot('teacher'), isNull);
  });

  Future<void> pumpProfile(
    WidgetTester tester,
    Widget page, {
    Locale locale = const Locale('ru'),
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = await tester.runAsync(
      () => store.readPreferences('teacher'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(
            AsyncData(
              AuthenticatedSession(
                ownerId: 'teacher',
                onboardingComplete: true,
              ),
            ),
          ),
          profileStoreProvider.overrideWithValue(store),
          teacherPreferencesProvider(
            'teacher',
          ).overrideWithValue(AsyncData(preferences)),
          profileAccountProvider('teacher').overrideWithValue(
            const AsyncData(ProfileAccountState(unavailable: true)),
          ),
        ],
        child: MaterialApp(
          theme: BuilderTheme.light,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'S50 shows truthful unavailable usage and three destinations at 360px',
    (tester) async {
      await pumpProfile(tester, const ProfilePage(ownerId: 'teacher'));
      expect(find.text('Данные о расходе пока недоступны'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('500'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('profile.help')),
        160,
      );
      expect(find.byKey(const Key('profile.settings')), findsOneWidget);
      expect(find.byKey(const Key('profile.privacy')), findsOneWidget);
      expect(find.byKey(const Key('profile.help')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('S54 saves selected grades without changing assistant language', (
    tester,
  ) async {
    await pumpProfile(tester, const ProfileSettingsPage(ownerId: 'teacher'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('profile.grade.5')),
      180,
    );
    await tester.tap(find.byKey(const Key('profile.grade.5')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('profile.savePreferences')),
      160,
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('profile.savePreferences')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final result = await tester.runAsync(
      () => store.readPreferences('teacher'),
    );
    expect(result!.setup.grades, {5, 7, 8});
    expect(result.setup.language, AssistantLanguage.kazakh);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S56 searches answers and shows empty results', (tester) async {
    await pumpProfile(tester, const ProfileHelpPage());
    await tester.enterText(
      find.byKey(const Key('profile.helpSearch')),
      'переустановке',
    );
    await tester.pumpAndSettle();
    expect(find.text('Где хранится мой ассистент?'), findsOneWidget);
    expect(find.text('Почему ИИ может ошибаться?'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('profile.helpSearch')),
      'zzzzzz',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Ничего не найдено. Попробуйте другой запрос.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy is localized and has no fake destructive controls', (
    tester,
  ) async {
    await pumpProfile(
      tester,
      const ProfilePrivacyPage(),
      locale: const Locale('kk'),
    );
    expect(find.text('Деректер қайда сақталады'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Аккаунтты жою'), 200);
    expect(find.textContaining('әзірге қолжетімсіз'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
