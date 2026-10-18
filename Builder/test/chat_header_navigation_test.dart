import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/app/router/app_router.dart';
import 'package:builder/features/assistant/presentation/assistant_chat_page.dart';
import 'package:builder/features/assistant/presentation/assistant_page.dart';
import 'package:builder/features/assistant/presentation/assistant_settings_page.dart';
import 'package:builder/features/assistant/presentation/local_data_settings_page.dart';
import 'package:builder/features/chat/presentation/conversation_history_sheet.dart';
import 'package:builder/features/models/presentation/model_selection_page.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:builder/ui_kit/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> openChat(
    WidgetTester tester, {
    bool direct = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(
          AsyncData(
            AuthenticatedSession(
              ownerId: 'header-test',
              onboardingComplete: true,
            ),
          ),
        ),
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
    if (direct) {
      router.go('/chat');
    } else {
      router.push('/chat');
    }
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'Chat header opens models and settings above chat and returns to it',
    (tester) async {
      final container = await openChat(tester);
      final router = container.read(appRouterProvider);
      for (final entry in [
        ('assistant.chooseModel', ModelSelectionPage),
        ('assistant.settingsBtn', AssistantSettingsPage),
      ]) {
        await tester.tap(find.byKey(Key(entry.$1)));
        await tester.pumpAndSettle();
        expect(find.byType(entry.$2), findsOneWidget);
        expect(find.byType(AssistantChatPage), findsNothing);
        expect(tester.takeException(), isNull);
        router.pop();
        await tester.pumpAndSettle();
        expect(find.byType(AssistantChatPage), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('assistant.settingsBtn')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('assistantSettings.localDataRow')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assistantSettings.localDataRow')));
      await tester.pumpAndSettle();
      expect(find.byType(LocalDataSettingsPage), findsOneWidget);
      expect(
        find.byKey(const Key('localData.retentionSegments')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AssistantSettingsPage), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AssistantChatPage), findsOneWidget);
      await tester.tap(find.byKey(const Key('assistant.historyBtn')));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationHistorySheet), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.back')));
      await tester.pumpAndSettle();
      expect(find.byType(AssistantPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Direct chat link back button returns to assistant', (
    tester,
  ) async {
    await openChat(tester, direct: true);
    await tester.tap(find.byKey(const Key('chat.back')));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
