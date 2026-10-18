import 'dart:async';

import 'package:builder/app/app.dart';
import 'package:builder/app/environment/app_config.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/app/router/app_router.dart';
import 'package:builder/features/onboarding/application/onboarding_controller.dart';
import 'package:builder/features/onboarding/domain/assistant_setup.dart';
import 'package:builder/features/onboarding/domain/initial_workspace_repository.dart';
import 'package:builder/features/policy/domain/policy_repository.dart';
import 'package:builder/features/policy/infrastructure/persistent_policy_repository.dart';
import 'package:builder/features/policy/policy_providers.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:builder/preview/onboarding_preview.dart';
import 'package:builder/ui_kit/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ChangingSession implements SessionRepository {
  SessionSnapshot current = AuthenticatedSession(
    ownerId: 'owner-a',
    onboardingComplete: false,
  );
  final changes = StreamController<SessionSnapshot>.broadcast();
  void set(SessionSnapshot value) {
    current = value;
    changes.add(value);
  }

  @override
  Stream<SessionSnapshot> watchSession() async* {
    yield current;
    yield* changes.stream;
  }
}

class TestWorkspaceRepository implements InitialWorkspaceRepository {
  int calls = 0;
  final saved = <String, InitialWorkspace>{};
  Completer<void>? pending;
  bool fail = false;
  bool wrongOwner = false;
  @override
  bool get isAvailable => true;
  @override
  Future<InitialWorkspace> createIfAbsent({
    required WorkspaceWritePermit permit,
    required AssistantSetup setup,
  }) async {
    final ownerId = permit.ownerId;
    calls++;
    if (pending != null) await pending!.future;
    if (!permit.isCurrent) throw const WorkspaceUnavailable();
    if (fail) throw StateError('private-path-and-database-details');
    if (wrongOwner) {
      return InitialWorkspace(ownerId: 'other-private-owner', setup: setup);
    }
    return saved.putIfAbsent(
      ownerId,
      () => InitialWorkspace(ownerId: ownerId, setup: setup),
    );
  }
}

Future<({ProviderContainer container, ChangingSession session})>
mountOnboarding(
  WidgetTester tester, {
  InitialWorkspaceRepository? repository,
  PolicyRepository? policyRepository,
  String locale = 'ru',
}) async {
  final session = ChangingSession();
  final policy =
      policyRepository ??
      (InMemoryPolicyRepository()..acknowledgePolicy(
        ownerId: 'owner-a',
        policyId: 'd02_cross_border_transfer',
        policyVersion: 'v1.0',
      ));
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(environment: AppEnvironment.development),
      ),
      sessionRepositoryProvider.overrideWithValue(session),
      policyRepositoryProvider.overrideWithValue(policy),
      if (repository != null)
        initialWorkspaceRepositoryProvider.overrideWithValue(repository),
    ],
  );
  container.read(appLocaleProvider.notifier).select(Locale(locale));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await session.changes.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const BuilderApp()),
  );
  await tester.pumpAndSettle();
  return (container: container, session: session);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(BuilderButton, label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> typeKey(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pump();
}

void prepare(OnboardingController controller, {String name = 'My helper'}) {
  controller.chooseSubject(SchoolSubject.mathematics);
  controller.toggleGrade(7);
  controller.setName(name);
}

void main() {
  test(
    'Setup validates grade bounds, owns its collection and normalizes only local text',
    () {
      final grades = <int>{7};
      final setup = AssistantSetup(
        subject: SchoolSubject.other,
        customSubject: ' Robotics ',
        grades: grades,
        language: AssistantLanguage.bilingual,
        name: ' Helper ',
      );
      grades.add(9);
      expect(setup.grades, {7});
      expect(() => setup.grades.add(9), throwsUnsupportedError);
      expect(setup.ready, isTrue);
      expect(setup.normalized().customSubject, 'Robotics');
      expect(setup.normalized().name, 'Helper');
      expect(
        AssistantSetup(
          subject: SchoolSubject.other,
          grades: {7},
        ).preferencesValid,
        isFalse,
      );
      expect(() => AssistantSetup(grades: {0}), throwsArgumentError);
      expect(() => AssistantSetup(grades: {12}), throwsArgumentError);
    },
  );

  test(
    'DEV preview creation is idempotent and accepts only the preview owner',
    () async {
      final repository = InMemoryOnboardingPreview();
      final setup = AssistantSetup(
        subject: SchoolSubject.biology,
        grades: {7},
        name: 'Helper',
      );
      final first = await repository.createIfAbsent(
        permit: WorkspaceWritePermit(
          ownerId: 'dev-onboarding-preview',
          canCommit: () => true,
        ),
        setup: setup,
      );
      final repeated = await repository.createIfAbsent(
        permit: WorkspaceWritePermit(
          ownerId: 'dev-onboarding-preview',
          canCommit: () => true,
        ),
        setup: setup.copyWith(name: 'Changed'),
      );
      expect(identical(first, repeated), isTrue);
      expect(repeated.setup.name, 'Helper');
      await expectLater(
        repository.createIfAbsent(
          permit: WorkspaceWritePermit(
            ownerId: 'real-owner',
            canCommit: () => true,
          ),
          setup: setup,
        ),
        throwsArgumentError,
      );
    },
  );

  testWidgets(
    'S01-S03: grade groups, separate language, back navigation and idempotent completion',
    (tester) async {
      final repository = TestWorkspaceRepository();
      final fixture = await mountOnboarding(tester, repository: repository);
      final container = fixture.container;
      expect(find.text('Соберите своего ассистента'), findsOneWidget);
      await tapButton(tester, 'Начать');
      expect(
        tester
            .widget<BuilderButton>(find.widgetWithText(BuilderButton, 'Далее'))
            .onPressed,
        isNull,
      );
      await tapKey(tester, 'onb.subject.mathematics');
      await tapKey(tester, 'onb.group.5');
      await tapKey(tester, 'onb.grade.6');
      await tapKey(tester, 'onb.language.kazakh');
      final provider = onboardingControllerProvider('owner-a');
      expect(container.read(provider).draft.grades, {5, 7});
      expect(container.read(appLocaleProvider)?.languageCode, 'ru');
      await tapButton(tester, 'Далее');
      expect(container.read(provider).draft.name, 'Ассистент: Математика');
      await typeKey(tester, 'onb.name', ' My teacher helper ');
      container.read(appRouterProvider).pop();
      await tester.pumpAndSettle();
      expect(container.read(provider).draft.name, ' My teacher helper ');
      await tapKey(tester, 'onb.subject.biology');
      await tapButton(tester, 'Далее');
      expect(container.read(provider).draft.name, ' My teacher helper ');
      await tapButton(tester, 'Создать ассистента');
      expect(repository.calls, 1);
      expect(repository.saved['owner-a']!.setup.name, 'My teacher helper');
      expect(repository.saved['owner-a']!.setup.subject, SchoolSubject.biology);
      expect(
        repository.saved['owner-a']!.setup.language,
        AssistantLanguage.kazakh,
      );
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/assistant',
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      container.read(appRouterProvider).go('/onboarding');
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/assistant',
      );
      expect(repository.calls, 1);
    },
  );

  testWidgets('Other subject requires its name; search never hides Other', (
    tester,
  ) async {
    final fixture = await mountOnboarding(tester);
    await tapButton(tester, 'Начать');
    await typeKey(tester, 'onb.search', 'No matching subject');
    expect(find.byKey(const Key('onb.subject.other')), findsOneWidget);
    await tapKey(tester, 'onb.subject.other');
    await tapKey(tester, 'onb.grade.11');
    expect(
      tester
          .widget<BuilderButton>(find.widgetWithText(BuilderButton, 'Далее'))
          .onPressed,
      isNull,
    );
    await typeKey(tester, 'onb.customSubject', 'Робототехника');
    await tapButton(tester, 'Далее');
    expect(
      fixture.container
          .read(onboardingControllerProvider('owner-a'))
          .draft
          .customSubject,
      'Робототехника',
    );
    expect(find.text('Робототехника'), findsOneWidget);
    expect(
      tester
          .widget<BuilderButton>(
            find.widgetWithText(BuilderButton, 'Создать ассистента'),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.textContaining('Сохранение ассистента пока недоступно'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Direct S03 cannot skip required preferences; logout closes every wizard route',
    (tester) async {
      final fixture = await mountOnboarding(tester);
      final router = fixture.container.read(appRouterProvider);
      router.go('/onboarding/assistant');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/onboarding/preferences',
      );
      fixture.session.set(const SignedOut());
      await tester.pumpAndSettle();
      final signedOutRouter = fixture.container.read(appRouterProvider);
      signedOutRouter.go('/onboarding/preferences');
      await tester.pumpAndSettle();
      expect(
        signedOutRouter.routeInformationProvider.value.uri.path,
        '/sign-in',
      );
      expect(find.byKey(const Key('onb.search')), findsNothing);
    },
  );

  testWidgets(
    'Write error preserves draft for retry and hides private diagnostics',
    (tester) async {
      final repository = TestWorkspaceRepository()..fail = true;
      final fixture = await mountOnboarding(tester, repository: repository);
      final controller = fixture.container.read(
        onboardingControllerProvider('owner-a').notifier,
      );
      prepare(controller, name: 'Keep this draft');
      fixture.container.read(appRouterProvider).go('/onboarding/assistant');
      await tester.pumpAndSettle();
      await tapButton(tester, 'Создать ассистента');
      expect(
        find.textContaining('Не удалось сохранить ассистента'),
        findsOneWidget,
      );
      expect(find.textContaining('private-path'), findsNothing);
      expect(
        fixture.container
            .read(onboardingControllerProvider('owner-a'))
            .draft
            .name,
        'Keep this draft',
      );
      repository.fail = false;
      await tapButton(tester, 'Создать ассистента');
      expect(repository.calls, 2);
      expect(repository.saved.length, 1);
    },
  );

  testWidgets(
    'Pending create is single-flight; old A result cannot complete new B or returning A',
    (tester) async {
      final repository = TestWorkspaceRepository()..pending = Completer<void>();
      final fixture = await mountOnboarding(tester, repository: repository);
      final container = fixture.container;
      final providerA = onboardingControllerProvider('owner-a');
      final subscription = container.listen(providerA, (_, _) {});
      addTearDown(subscription.close);
      final controllerA = container.read(providerA.notifier);
      prepare(controllerA, name: 'A private draft');
      final request = controllerA.create();
      await tester.pump();
      await controllerA.create();
      expect(repository.calls, 1);
      fixture.session.set(
        AuthenticatedSession(ownerId: 'owner-b', onboardingComplete: false),
      );
      await tester.pumpAndSettle();
      expect(container.read(providerA).draft.name, isEmpty);
      expect(
        container.read(onboardingControllerProvider('owner-b')).draft.name,
        isEmpty,
      );
      fixture.session.set(
        AuthenticatedSession(ownerId: 'owner-a', onboardingComplete: false),
      );
      await tester.pumpAndSettle();
      repository.pending!.complete();
      await request;
      await tester.pumpAndSettle();
      expect(repository.saved, isEmpty);
      expect(container.read(providerA).completed, isFalse);
      expect(container.read(providerA).draft.name, isEmpty);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/onboarding',
      );
    },
  );

  testWidgets(
    'Disposed scope revokes an in-flight write before repository commit',
    (tester) async {
      final repository = TestWorkspaceRepository()..pending = Completer<void>();
      final fixture = await mountOnboarding(tester, repository: repository);
      final controller = fixture.container.read(
        onboardingControllerProvider('owner-a').notifier,
      );
      prepare(controller);
      final pending = controller.create();
      await tester.pump();
      fixture.container.invalidate(onboardingControllerProvider('owner-a'));
      await tester.pump();
      repository.pending!.complete();
      await pending;
      await tester.pumpAndSettle();
      expect(repository.saved, isEmpty);
      expect(
        fixture.container
            .read(onboardingControllerProvider('owner-a'))
            .completed,
        isFalse,
      );
    },
  );

  testWidgets('Grade group toggles are exact and reject out-of-range input', (
    tester,
  ) async {
    final fixture = await mountOnboarding(tester);
    final controller = fixture.container.read(
      onboardingControllerProvider('owner-a').notifier,
    );
    final provider = onboardingControllerProvider('owner-a');
    controller.toggleGradeGroup(1, 4);
    expect(fixture.container.read(provider).draft.grades, {1, 2, 3, 4});
    controller.toggleGradeGroup(1, 4);
    expect(fixture.container.read(provider).draft.grades, isEmpty);
    expect(() => controller.toggleGrade(12), throwsArgumentError);
    expect(() => controller.toggleGradeGroup(8, 7), throwsArgumentError);
  });

  testWidgets('Wrong-owner repository result never grants workspace access', (
    tester,
  ) async {
    final repository = TestWorkspaceRepository()..wrongOwner = true;
    final fixture = await mountOnboarding(tester, repository: repository);
    final provider = onboardingControllerProvider('owner-a');
    final controller = fixture.container.read(provider.notifier);
    prepare(controller);
    await controller.create();
    expect(fixture.container.read(provider).completed, isFalse);
    expect(
      fixture.container.read(provider).failure,
      OnboardingFailure.saveFailed,
    );
  });

  testWidgets('Unavailable storage never fabricates a completed assistant', (
    tester,
  ) async {
    final fixture = await mountOnboarding(tester);
    final provider = onboardingControllerProvider('owner-a');
    final controller = fixture.container.read(provider.notifier);
    prepare(controller);
    await controller.create();
    expect(fixture.container.read(provider).completed, isFalse);
    expect(
      fixture.container.read(provider).failure,
      OnboardingFailure.unavailable,
    );
    expect(
      fixture.container.read(sessionProvider).requireValue,
      isA<AuthenticatedSession>(),
    );
  });

  for (final locale in ['ru', 'kk']) {
    testWidgets(
      '$locale onboarding fits 320px/130% and keyboard, with visible footer',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final fixture = await mountOnboarding(tester, locale: locale);
        expect(tester.takeException(), isNull);
        final controller = fixture.container.read(
          onboardingControllerProvider('owner-a').notifier,
        );
        prepare(controller);
        final router = fixture.container.read(appRouterProvider);
        for (final route in [
          '/onboarding/preferences',
          '/onboarding/assistant',
        ]) {
          router.go(route);
          await tester.pumpAndSettle();
          final field = find.byKey(
            Key(route.endsWith('assistant') ? 'onb.name' : 'onb.search'),
          );
          await tester.ensureVisible(field);
          await tester.tap(field);
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(BuilderButton), findsOneWidget);
          final bottom = tester.getBottomRight(find.byType(BuilderButton));
          expect(bottom.dy, lessThanOrEqualTo(380));
          tester.view.resetViewInsets();
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
    );
  }
}
