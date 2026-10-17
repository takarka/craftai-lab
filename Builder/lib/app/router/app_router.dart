import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/session/session_repository.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/auth_page.dart';
import '../localization/app_localizations.dart';
import '../presentation/foundation_pages.dart';
import '../providers.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // Replace navigation stacks when account ownership changes.
  ref.watch(
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
            ].contains(path)
            ? null
            : '/sign-in';
      }
      final account = value as AuthenticatedSession;
      if (!account.onboardingComplete) {
        return path == '/onboarding' ? null : '/onboarding';
      }
      if (const [
        '/startup',
        '/sign-in',
        '/register',
        '/recover-password',
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
        builder: (context, state) => const OnboardingPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => BuilderShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/assistant',
                builder: (context, state) => FoundationPage(
                  title: AppLocalizations.of(context).assistantTab,
                  message: AppLocalizations.of(context).assistantPending,
                ),
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
