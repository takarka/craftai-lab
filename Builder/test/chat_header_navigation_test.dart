import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/app/router/app_router.dart';
import 'package:builder/demo/demo_app.dart';
import 'package:builder/demo/demo_http_client.dart';
import 'package:builder/features/agents/agents_providers.dart';
import 'package:builder/features/agents/presentation/agents_page.dart';
import 'package:builder/features/lab_runtime/presentation/lab_agent_chat_page.dart';
import 'package:builder/features/lab_runtime/presentation/lab_agent_settings_page.dart';
import 'package:builder/features/lab_runtime/presentation/lab_agent_workspace_page.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:builder/ui_kit/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> openAgentRoute(
    WidgetTester tester,
    String path,
  ) async {
    final environment = await DemoEnvironment.create();
    addTearDown(environment.client.close);
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(
          AsyncData(
            AuthenticatedSession(
              ownerId: DemoHttpClient.ownerId,
              onboardingComplete: true,
            ),
          ),
        ),
        agentsRepositoryProvider(
          DemoHttpClient.ownerId,
        ).overrideWithValue(environment.agents),
        labRuntimeApiProvider.overrideWithValue(environment.runtime),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: BuilderTheme.light,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.go(path);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('Agent chat opens settings and returns to the same agent', (
    tester,
  ) async {
    await openAgentRoute(tester, '/agents/demo-math/chat');
    expect(find.byType(LabAgentChatPage), findsOneWidget);
    expect(find.text('Математика · 5 класс'), findsOneWidget);
    await tester.tap(find.byTooltip('Настройки агента'));
    await tester.pumpAndSettle();
    expect(find.byType(LabAgentSettingsPage), findsOneWidget);
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(LabAgentChatPage), findsOneWidget);
    expect(find.text('Математика · 5 класс'), findsOneWidget);
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(AgentEditorPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Direct agent settings link opens the selected agent', (
    tester,
  ) async {
    await openAgentRoute(tester, '/agents/demo-russian/settings');
    expect(find.byType(LabAgentSettingsPage), findsOneWidget);
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(LabAgentChatPage), findsOneWidget);
    expect(find.text('Русский язык · 7 класс'), findsOneWidget);
    expect(find.text('Математика · 5 класс'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
