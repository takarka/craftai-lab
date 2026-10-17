import 'dart:async';

import 'package:builder/app/app.dart';
import 'package:builder/app/environment/app_config.dart';
import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/app/router/app_router.dart';
import 'package:builder/core/platform/platform_capabilities.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ControlledSessionRepository implements SessionRepository {
  final controller = StreamController<SessionSnapshot>();
  @override
  Stream<SessionSnapshot> watchSession() => controller.stream;
}

void main() {
  group('Public configuration', () {
    test('Missing endpoint stays unconfigured, never guesses a server', () {
      final config = AppConfig.fromValues(environment: 'prod', apiBaseUrl: '');
      expect(config.environment, AppEnvironment.production);
      expect(config.apiBaseUri, isNull);
    });

    test('HTTPS endpoint with API path is accepted', () {
      final config = AppConfig.fromValues(
        environment: 'staging',
        apiBaseUrl: 'https://craftai.example/api/v1',
      );
      expect(config.apiBaseUri!.path, '/api/v1');
    });

    for (final endpoint in [
      'http://craftai.example',
      '/api',
      'https://user:secret@craftai.example',
      'https://craftai.example?token=secret',
      'https://craftai.example#secret',
      'ftp://craftai.example',
    ]) {
      test('Invalid URL is rejected without reflecting private contents', () {
        expect(
          () => AppConfig.fromValues(environment: 'prod', apiBaseUrl: endpoint),
          throwsA(
            isA<FormatException>().having(
              (error) => error.toString().contains('secret'),
              'leaks secret',
              false,
            ),
          ),
        );
      });
    }

    test('Only dev accepts HTTP loopback; unknown environment fails', () {
      for (final endpoint in [
        'http://localhost:8000',
        'http://127.0.0.1:8000',
        'http://[::1]:8000',
      ]) {
        expect(
          AppConfig.fromValues(
            environment: 'dev',
            apiBaseUrl: endpoint,
          ).apiBaseUri,
          isNotNull,
        );
        expect(
          () => AppConfig.fromValues(environment: 'prod', apiBaseUrl: endpoint),
          throwsFormatException,
        );
      }
      expect(
        () => AppConfig.fromValues(
          environment: 'dev',
          apiBaseUrl: 'http://craftai.example',
        ),
        throwsFormatException,
      );
      expect(
        () => AppConfig.fromValues(environment: 'typo', apiBaseUrl: ''),
        throwsFormatException,
      );
    });
  });

  test(
    'Platform capability does not claim permission or native availability',
    () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(
          PlatformCapabilities.forPlatform(
            platform: platform,
            isWeb: false,
          ).nativeActions,
          CapabilitySupport.requiresNativeVerification,
        );
        expect(
          PlatformCapabilities.forPlatform(
            platform: platform,
            isWeb: true,
          ).nativeActions,
          CapabilitySupport.unsupported,
        );
      }
      expect(
        PlatformCapabilities.forPlatform(
          platform: TargetPlatform.linux,
          isWeb: false,
        ).nativeActions,
        CapabilitySupport.unsupported,
      );
    },
  );

  test('Authenticated owner ID is mandatory', () {
    expect(
      () => AuthenticatedSession(ownerId: ' ', onboardingComplete: true),
      throwsArgumentError,
    );
  });

  testWidgets(
    'Production entry has no gallery, fabricated session or demo login',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(environment: AppEnvironment.production),
            ),
          ],
          child: const BuilderApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Craft Builder'), findsOneWidget);
      expect(
        find.textContaining('Вход и регистрация пока недоступны'),
        findsOneWidget,
      );
      expect(find.text('UI Kit'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(TextField), findsNWidgets(2));
    },
  );

  testWidgets('Invalid configuration shows a safe localized page', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: BuilderApp()));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Не удалось запустить приложение'),
      findsOneWidget,
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ru', 'kk']) {
    testWidgets(
      '$language: guards handle loading, onboarding, tab switch, account switch and logout',
      (tester) async {
        final repository = ControlledSessionRepository();
        final container = ProviderContainer(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(environment: AppEnvironment.development),
            ),
            sessionRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          await repository.controller.close();
        });
        container.read(appLocaleProvider.notifier).select(Locale(language));
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const BuilderApp(),
          ),
        );
        await tester.pump();
        expect(
          container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/startup',
        );
        repository.controller.add(const SignedOut());
        await tester.pumpAndSettle();
        var router = container.read(appRouterProvider);
        router.go('/profile');
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/sign-in');
        expect(find.byType(NavigationBar), findsNothing);

        repository.controller.add(
          AuthenticatedSession(ownerId: 'fixture-a', onboardingComplete: false),
        );
        await tester.pumpAndSettle();
        router = container.read(appRouterProvider);
        expect(router.routeInformationProvider.value.uri.path, '/onboarding');
        router.go('/course');
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/onboarding');

        repository.controller.add(
          AuthenticatedSession(ownerId: 'fixture-a', onboardingComplete: true),
        );
        await tester.pumpAndSettle();
        final strings = AppLocalizations.of(
          tester.element(find.byType(NavigationBar)),
        );
        expect(find.byType(NavigationDestination), findsNWidgets(3));
        await tester.tap(find.text(strings.courseTab).last);
        await tester.pumpAndSettle();
        expect(
          container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/course',
        );

        final previousRouter = container.read(appRouterProvider);
        repository.controller.add(
          AuthenticatedSession(ownerId: 'fixture-b', onboardingComplete: true),
        );
        await tester.pumpAndSettle();
        router = container.read(appRouterProvider);
        expect(identical(router, previousRouter), isFalse);
        expect(router.routeInformationProvider.value.uri.path, '/assistant');
        repository.controller.add(const SignedOut());
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsNothing);
        expect(
          container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/sign-in',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Locale changes without claiming to change assistant language', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(environment: AppEnvironment.development),
          ),
        ],
        child: const BuilderApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Язык интерфейса'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Қазақша'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Интерфейс тілі'), findsOneWidget);
    expect(
      find.textContaining('Кіру және тіркелу әзірге қолжетімсіз'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Session errors close protected routes without exposing details',
    (tester) async {
      final repository = ControlledSessionRepository();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await repository.controller.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(environment: AppEnvironment.development),
            ),
            sessionRepositoryProvider.overrideWithValue(repository),
          ],
          child: const BuilderApp(),
        ),
      );
      await tester.pump();
      repository.controller.add(
        AuthenticatedSession(ownerId: 'fixture', onboardingComplete: true),
      );
      await tester.pumpAndSettle();
      repository.controller.addError(StateError('private token and payload'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        find.textContaining('Не удалось проверить сессию'),
        findsOneWidget,
      );
      expect(find.textContaining('private token'), findsNothing);
    },
  );
}
