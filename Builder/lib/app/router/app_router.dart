import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/session/session_repository.dart';
import '../../features/assistant/presentation/assistant_page.dart';
import '../../features/models/presentation/model_selection_page.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/auth_page.dart';
import '../../features/onboarding/application/onboarding_controller.dart';
import '../../features/onboarding/presentation/onboarding_pages.dart';
import '../localization/app_localizations.dart';
import '../presentation/foundation_pages.dart';
import '../providers.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // Replace navigation stacks when account ownership changes.
  final ownerId = ref.watch(
    sessionProvider.select((state) {
      final session = state.asData?.value;
      return session is AuthenticatedSession ? session.ownerId : null;
    }),
  );
  final router = GoRouter(
    navigatorKey: GlobalKey<NavigatorState>(),
    initialLocation: '/assistant',
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final path = state.uri.path;
      final legal = const ['/legal/terms', '/legal/privacy'].contains(path);
      if (legal) return null;
      if (!session.hasValue || session.hasError) {
        return path == '/startup' ? null : '/startup';
      }
      final value = session.requireValue;
      if (value is SignedOut) {
        return const [
              '/sign-in',
              '/register',
              '/recover-password',
              '/reset-password',
            ].contains(path)
            ? null
            : '/sign-in';
      }
      final account = value as AuthenticatedSession;
      final onboarding = ref.read(
        onboardingControllerProvider(account.ownerId),
      );
      final complete = account.onboardingComplete || onboarding.completed;
      if (!complete) {
        if (path == '/onboarding/assistant' &&
            !onboarding.draft.preferencesValid) {
          return '/onboarding/preferences';
        }
        return const [
              '/onboarding',
              '/onboarding/preferences',
              '/onboarding/assistant',
            ].contains(path)
            ? null
            : '/onboarding';
      }
      if (path.startsWith('/onboarding/')) return '/assistant';
      if (const [
        '/startup',
        '/sign-in',
        '/register',
        '/recover-password',
        '/reset-password',
        '/onboarding',
        '/',
      ].contains(path)) {
        return '/assistant';
      }
      return null;
    },
    errorBuilder: (context, state) => FoundationPage(
      title: AppLocalizations.of(context).unavailableTitle,
      message: AppLocalizations.of(context).featurePending,
    ),
    routes: [
      GoRoute(
        path: '/startup',
        builder: (context, state) => const StartupPage(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const AuthPage(kind: AuthFormKind.signIn),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) =>
            const AuthPage(kind: AuthFormKind.register),
      ),
      GoRoute(
        path: '/recover-password',
        builder: (context, state) =>
            const AuthPage(kind: AuthFormKind.recovery),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) {
          final token = state.uri.queryParameters['token'] ??
              state.uri.queryParameters['t'];
          return AuthPage(
            kind: AuthFormKind.resetPassword,
            resetToken: token,
          );
        },
      ),
      GoRoute(
        path: '/legal/terms',
        pageBuilder: (context, state) => MaterialPage<void>(
          key: state.pageKey,
          fullscreenDialog: true,
          child: const AuthLegalPage(privacy: false),
        ),
      ),
      GoRoute(
        path: '/legal/privacy',
        pageBuilder: (context, state) => MaterialPage<void>(
          key: state.pageKey,
          fullscreenDialog: true,
          child: const AuthLegalPage(privacy: true),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingWelcomePage(),
      ),
      GoRoute(
        path: '/onboarding/preferences',
        builder: (context, state) =>
            OnboardingPreferencesPage(ownerId: ownerId!),
      ),
      GoRoute(
        path: '/onboarding/assistant',
        builder: (context, state) => OnboardingAssistantPage(ownerId: ownerId!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => BuilderShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/assistant',
                builder: (context, state) => AssistantPage(ownerId: ownerId!),
                routes: [
                  GoRoute(
                    path: 'models',
                    builder: (context, state) =>
                        ModelSelectionPage(ownerId: ownerId!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/course',
                builder: (context, state) => FoundationPage(
                  title: AppLocalizations.of(context).courseTab,
                  message: AppLocalizations.of(context).coursePending,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => FoundationPage(
                  title: AppLocalizations.of(context).profileTab,
                  message: AppLocalizations.of(context).profilePending,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.listen(sessionProvider, (previous, next) => router.refresh());
  if (ownerId != null) {
    ref.listen(
      onboardingControllerProvider(ownerId).select((state) => state.completed),
      (_, _) => router.refresh(),
    );
  }
  ref.onDispose(router.dispose);
  return router;
});

class BuilderShell extends StatelessWidget {
  const BuilderShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.smart_toy_outlined),
            label: strings.assistantTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.school_outlined),
            label: strings.courseTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            label: strings.profileTab,
          ),
        ],
      ),
    );
  }
}
