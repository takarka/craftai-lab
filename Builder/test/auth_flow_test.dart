import 'dart:async';

import 'package:builder/app/app.dart';
import 'package:builder/app/environment/app_config.dart';
import 'package:builder/app/localization/app_localizations_ru.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/app/router/app_router.dart';
import 'package:builder/core/errors/app_failure.dart';
import 'package:builder/features/auth/application/auth_controller.dart';
import 'package:builder/features/auth/domain/auth_gateway.dart';
import 'package:builder/features/auth/presentation/auth_validation.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:builder/ui_kit/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Test-only transport. It never enters the app source or production bootstrap.
class TestAuthGateway implements AuthGateway {
  bool available = true;
  bool withDocuments = true;
  bool emptyDocuments = false;
  int calls = 0;
  String? email;
  String? password;
  String? name;
  String? termsRevision;
  String? privacyRevision;
  Object? failure;
  Completer<void>? pending;
  @override
  bool get isAvailable => available;
  @override
  AuthLegalDocuments? documentsFor(String languageCode) => withDocuments
      ? AuthLegalDocuments(
          terms: LegalDocument(
            body: emptyDocuments ? '' : 'TEST TERMS $languageCode',
            revision: 'terms-$languageCode-v1',
          ),
          privacy: LegalDocument(
            body: 'TEST PRIVACY $languageCode',
            revision: 'privacy-$languageCode-v2',
          ),
        )
      : null;
  Future<void> _complete() async {
    calls++;
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> signIn({required String email, required String password}) {
    this.email = email;
    this.password = password;
    return _complete();
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String termsRevision,
    required String privacyRevision,
  }) {
    this.name = name;
    this.email = email;
    this.password = password;
    this.termsRevision = termsRevision;
    this.privacyRevision = privacyRevision;
    return _complete();
  }

  @override
  Future<void> requestPasswordReset({required String email}) {
    this.email = email;
    return _complete();
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) {
    password = newPassword;
    return _complete();
  }
}

class ReadySessionRepository implements SessionRepository {
  @override
  Stream<SessionSnapshot> watchSession() => Stream.value(
    AuthenticatedSession(ownerId: 'test-owner', onboardingComplete: true),
  );
}

Future<ProviderContainer> mount(
  WidgetTester tester, {
  TestAuthGateway? gateway,
  String locale = 'ru',
  SessionRepository? sessionRepository,
}) async {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(environment: AppEnvironment.development),
      ),
      if (gateway != null) authGatewayProvider.overrideWithValue(gateway),
      if (sessionRepository != null)
        sessionRepositoryProvider.overrideWithValue(sessionRepository),
    ],
  );
  container.read(appLocaleProvider.notifier).select(Locale(locale));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const BuilderApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder input(String name) => find.descendant(
  of: find.byKey(Key('auth.$name')),
  matching: find.byType(TextFormField),
  matchRoot: true,
);

Future<void> enter(WidgetTester tester, String name, String value) async {
  await tester.ensureVisible(input(name));
  await tester.enterText(input(name), value);
  await tester.pump();
}

Future<void> submit(WidgetTester tester, String label) async {
  final button = find.widgetWithText(BuilderButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

void main() {
  test(
    'Validation trims email and name but never invents or trims password policy',
    () {
      final strings = AppLocalizationsRu();
      expect(AuthValidation.email(' person@school.kz ', strings), isNull);
      for (final value in ['user', '@school.kz', 'user@', 'a b@school.kz']) {
        expect(AuthValidation.email(value, strings), strings.invalidEmail);
      }
      expect(AuthValidation.requiredText('  ', strings), strings.fieldRequired);
      expect(AuthValidation.password('', strings), strings.fieldRequired);
      expect(AuthValidation.password(' a ', strings), isNull);
      expect(
        AuthValidation.confirmation('a', ' a ', strings),
        strings.passwordMismatch,
      );
    },
  );

  testWidgets(
    'No adapter: forms are visible but cannot authenticate or register',
    (tester) async {
      final container = await mount(tester);
      final button = tester.widget<BuilderButton>(
        find.widgetWithText(BuilderButton, 'Войти'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.textContaining('Вход и регистрация пока недоступны'),
        findsOneWidget,
      );
      container.read(appRouterProvider).go('/register');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('auth.consent')))
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<BuilderButton>(
              find.widgetWithText(BuilderButton, 'Создать аккаунт'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets(
    'Login validates, toggles password, redacts error and clears secret',
    (tester) async {
      final gateway = TestAuthGateway()
        ..failure = const AppFailure(AppFailureCode.invalidCredentials);
      await mount(tester, gateway: gateway);
      await submit(tester, 'Войти');
      await tester.pumpAndSettle();
      expect(gateway.calls, 0);
      expect(find.text('Заполните поле.'), findsNWidgets(2));
      await enter(tester, 'email', 'invalid');
      await enter(tester, 'password', ' secret ');
      await submit(tester, 'Войти');
      expect(gateway.calls, 0);
      await enter(tester, 'email', ' teacher@school.kz ');
      await tester.ensureVisible(find.byTooltip('Показать пароль'));
      await tester.tap(find.byTooltip('Показать пароль'));
      await tester.pump();
      expect(
        tester.widget<TextFormField>(input('password')).controller!.text,
        ' secret ',
      );
      expect(find.byTooltip('Скрыть пароль'), findsOneWidget);
      await submit(tester, 'Войти');
      await tester.pumpAndSettle();
      expect(gateway.calls, 1);
      expect(gateway.email, 'teacher@school.kz');
      expect(gateway.password, ' secret ');
      expect(find.text('Неверная почта или пароль.'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(input('password')).controller!.text,
        isEmpty,
      );
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets(
    'Pending submit is single-flight; completion never creates a session',
    (tester) async {
      final gateway = TestAuthGateway()..pending = Completer<void>();
      final container = await mount(tester, gateway: gateway);
      await enter(tester, 'email', 'a@school.kz');
      await enter(tester, 'password', 'password');
      await submit(tester, 'Войти');
      await tester.pump();
      expect(gateway.calls, 1);
      final controller = container.read(
        authControllerProvider(AuthFormKind.signIn).notifier,
      );
      await controller.submit(
        (g) => g.signIn(email: 'duplicate@school.kz', password: 'duplicate'),
      );
      expect(gateway.calls, 1);
      gateway.pending!.complete();
      await tester.pumpAndSettle();
      expect(container.read(sessionProvider).requireValue, isA<SignedOut>());
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/sign-in',
      );
    },
  );

  testWidgets(
    'Passwords clear on background and on navigation to registration',
    (tester) async {
      final container = await mount(tester);
      await enter(tester, 'password', 'private');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(
        tester.widget<TextFormField>(input('password')).controller!.text,
        isEmpty,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await enter(tester, 'password', 'other-private');
      await submit(tester, 'Создать аккаунт');
      await tester.pumpAndSettle();
      container.read(appRouterProvider).pop();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(input('password')).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets('Leaving an unverified form cancels system autofill saving', (
    tester,
  ) async {
    final container = await mount(tester);
    await enter(tester, 'email', 'person@school.kz');
    await enter(tester, 'password', 'not-authenticated');
    tester.testTextInput.log.clear();
    container.read(appRouterProvider).go('/recover-password');
    await tester.pumpAndSettle();
    final finish = tester.testTextInput.log.where(
      (call) => call.method == 'TextInput.finishAutofillContext',
    );
    expect(finish, isNotEmpty);
    expect(finish.every((call) => call.arguments == false), isTrue);
  });

  testWidgets(
    'Registration needs approved documents, consent and matching password',
    (tester) async {
      final gateway = TestAuthGateway()
        ..failure = const AppFailure(AppFailureCode.accountExists);
      final container = await mount(tester, gateway: gateway);
      container.read(appRouterProvider).go('/register');
      await tester.pumpAndSettle();
      await enter(tester, 'name', ' Teacher ');
      await enter(tester, 'email', ' teacher@school.kz ');
      await enter(tester, 'password', 'password-one');
      await enter(tester, 'confirmPassword', 'wrong');
      expect(
        tester
            .widget<BuilderButton>(
              find.widgetWithText(BuilderButton, 'Создать аккаунт'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byKey(const Key('auth.consent')));
      await tester.tap(find.byKey(const Key('auth.consent')));
      await submit(tester, 'Создать аккаунт');
      await tester.pumpAndSettle();
      expect(gateway.calls, 0);
      expect(find.text('Пароли не совпадают.'), findsOneWidget);
      await enter(tester, 'confirmPassword', 'password-one');
      await submit(tester, 'Создать аккаунт');
      await tester.pumpAndSettle();
      expect(gateway.calls, 1);
      expect(gateway.name, 'Teacher');
      expect(gateway.termsRevision, 'terms-ru-v1');
      expect(gateway.privacyRevision, 'privacy-ru-v2');
      expect(
        find.text('У вас уже есть аккаунт CraftAI — войдите.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(input('confirmPassword')).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets('Changing document locale requires consent again', (
    tester,
  ) async {
    final gateway = TestAuthGateway();
    final container = await mount(tester, gateway: gateway);
    container.read(appRouterProvider).go('/register');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('auth.consent')));
    await tester.tap(find.byKey(const Key('auth.consent')));
    await tester.pump();
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('auth.consent')))
          .value,
      isTrue,
    );
    container.read(appLocaleProvider.notifier).select(const Locale('kk'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('auth.consent')))
          .value,
      isFalse,
    );
  });

  testWidgets('Available gateway without documents still blocks registration', (
    tester,
  ) async {
    final gateway = TestAuthGateway()..withDocuments = false;
    final container = await mount(tester, gateway: gateway);
    container.read(appRouterProvider).go('/register');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BuilderButton>(
            find.widgetWithText(BuilderButton, 'Создать аккаунт'),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.textContaining('До их публикации регистрация отключена'),
      findsOneWidget,
    );
    expect(gateway.calls, 0);
  });

  testWidgets('Empty policy text is not treated as available consent', (
    tester,
  ) async {
    final gateway = TestAuthGateway()..emptyDocuments = true;
    final container = await mount(tester, gateway: gateway);
    container.read(appRouterProvider).go('/register');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('auth.consent')))
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<BuilderButton>(
            find.widgetWithText(BuilderButton, 'Создать аккаунт'),
          )
          .onPressed,
      isNull,
    );
  });

  test(
    'Late request completion cannot update a disposed auth controller',
    () async {
      final gateway = TestAuthGateway()..pending = Completer<void>();
      final container = ProviderContainer(
        overrides: [authGatewayProvider.overrideWithValue(gateway)],
      );
      final provider = authControllerProvider(AuthFormKind.signIn);
      final subscription = container.listen(provider, (_, _) {});
      final request = container
          .read(provider.notifier)
          .submit((g) => g.signIn(email: 'a@school.kz', password: 'private'));
      expect(container.read(provider).busy, isTrue);
      subscription.close();
      container.dispose();
      gateway.pending!.complete();
      await expectLater(request, completes);
    },
  );

  testWidgets(
    'Recovery shows generic confirmation only after successful request',
    (tester) async {
      final gateway = TestAuthGateway()
        ..failure = const AppFailure(AppFailureCode.networkUnavailable);
      final container = await mount(tester, gateway: gateway);
      container.read(appRouterProvider).go('/recover-password');
      await tester.pumpAndSettle();
      await enter(tester, 'email', 'person@school.kz');
      await submit(tester, 'Отправить ссылку');
      await tester.pumpAndSettle();
      expect(find.textContaining('Проверьте интернет'), findsOneWidget);
      expect(find.text('Проверьте почту'), findsNothing);
      gateway.failure = null;
      await submit(tester, 'Отправить ссылку');
      await tester.pumpAndSettle();
      expect(find.text('Проверьте почту'), findsOneWidget);
      expect(
        find.textContaining('Если аккаунт с этой почтой существует'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('auth.email')), findsNothing);
      expect(gateway.calls, 2);
    },
  );

  testWidgets('Unknown adapter exceptions never expose private payloads', (
    tester,
  ) async {
    final gateway = TestAuthGateway()
      ..failure = StateError('secret-token-and-private-response');
    await mount(tester, gateway: gateway);
    await enter(tester, 'email', 'person@school.kz');
    await enter(tester, 'password', 'password');
    await submit(tester, 'Войти');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Не удалось выполнить действие'),
      findsOneWidget,
    );
    expect(find.textContaining('secret-token'), findsNothing);
  });

  testWidgets('Legal root page preserves the authenticated tab stack', (
    tester,
  ) async {
    final container = await mount(
      tester,
      gateway: TestAuthGateway(),
      sessionRepository: ReadySessionRepository(),
    );
    final router = container.read(appRouterProvider);
    router.go('/profile');
    await tester.pumpAndSettle();
    router.push('/legal/privacy');
    await tester.pumpAndSettle();
    expect(find.text('TEST PRIVACY ru'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/profile');
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  for (final locale in ['ru', 'kk']) {
    testWidgets(
      '$locale auth forms fit small screen, 130% text and open keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final container = await mount(tester, locale: locale);
        for (final route in ['/sign-in', '/register', '/recover-password']) {
          container.read(appRouterProvider).go(route);
          await tester.pumpAndSettle();
          await tester.ensureVisible(input('email'));
          await tester.tap(input('email'));
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          await tester.pumpAndSettle();
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -500),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.resetViewInsets();
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
    );
  }
}
