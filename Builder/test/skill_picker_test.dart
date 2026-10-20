import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/features/assistant/presentation/assistant_chat_page.dart';
import 'package:builder/features/chat/chat_providers.dart';
import 'package:builder/features/chat/domain/conversation.dart';
import 'package:builder/features/policy/infrastructure/persistent_policy_repository.dart';
import 'package:builder/features/policy/policy_providers.dart';
import 'package:builder/features/skills/domain/skill_scenario.dart';
import 'package:builder/features/skills/domain/skill_templates.dart';
import 'package:builder/features/skills/domain/skills_repository.dart';
import 'package:builder/features/skills/skills_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository implements SkillsRepository {
  _Repository(this.skills);
  final List<SkillScenario> skills;
  @override
  Future<List<SkillScenario>> getSkills(String ownerId) async => skills;
  @override
  Future<void> saveSkill(String ownerId, SkillScenario skill) async {}
  @override
  Future<void> deleteSkill(String ownerId, String skillId) async {}
}

class _Chat extends ChatSessionNotifier {
  _Chat() : super('alice');
  final sent = <String>[];
  @override
  ChatState build() => ChatState(
    activeConversation: Conversation(
      id: 'conversation',
      ownerId: 'alice',
      title: 'Chat',
      createdAtUtc: DateTime.utc(2026),
      activityAtUtc: DateTime.utc(2026),
    ),
  );
  @override
  Future<void> sendMessage(String text) async {
    sent.add(text);
  }
}

Future<_Chat> _open(WidgetTester tester, List<SkillScenario> skills) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final chat = _Chat();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        skillsRepositoryProvider.overrideWithValue(_Repository(skills)),
        chatSessionProvider('alice').overrideWith(() => chat),
        policyRepositoryProvider.overrideWithValue(InMemoryPolicyRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: const AssistantChatPage(ownerId: 'alice'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return chat;
}

void main() {
  testWidgets(
    'Skill is picked in chat, inputs filled, then card can be cancelled',
    (tester) async {
      final skill = SkillTemplates.forLocale().first;
      final chat = await _open(tester, [skill]);
      expect(find.byKey(const Key('skill.send')), findsNothing);

      await tester.tap(find.byKey(const Key('chat.skillsBtn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('skillPicker.${skill.id}')));
      await tester.pumpAndSettle();

      // Missing input is refused.
      await tester.tap(find.byKey(const Key('skillPicker.continue')));
      await tester.pumpAndSettle();
      expect(find.text('Укажите эти данные'), findsNWidgets(2));

      await tester.enterText(
        find.byKey(const Key('skillPicker.input.Тема')),
        'Дроби',
      );
      await tester.enterText(
        find.byKey(const Key('skillPicker.input.Класс')),
        '5',
      );
      await tester.tap(find.byKey(const Key('skillPicker.continue')));
      await tester.pumpAndSettle();

      // Nothing is sent until the user presses "Запустить".
      expect(chat.sent, isEmpty);
      expect(find.byKey(const Key('skill.send')), findsOneWidget);
      expect(find.text('Тема: Дроби'), findsOneWidget);
      expect(find.text('Класс: 5'), findsOneWidget);

      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skill.send')), findsNothing);
      expect(chat.sent, isEmpty);
    },
  );

  testWidgets('Picked skill sends once after D02 consent', (tester) async {
    final skill = SkillTemplates.forLocale().first;
    final chat = await _open(tester, [skill]);
    await tester.tap(find.byKey(const Key('chat.skillsBtn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('skillPicker.${skill.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('skillPicker.input.Тема')),
      'Дроби',
    );
    await tester.enterText(
      find.byKey(const Key('skillPicker.input.Класс')),
      '5',
    );
    await tester.tap(find.byKey(const Key('skillPicker.continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill.send')));
    await tester.pumpAndSettle();
    final consent = find.byKey(const Key('d02.understand'));
    await tester.ensureVisible(consent);
    await tester.pumpAndSettle();
    await tester.tap(consent);
    await tester.pumpAndSettle();
    expect(chat.sent, hasLength(1));
    expect(find.byKey(const Key('skill.send')), findsNothing);
  });

  testWidgets('Empty skill list offers to create a skill', (tester) async {
    await _open(tester, []);
    await tester.tap(find.byKey(const Key('chat.skillsBtn')));
    await tester.pumpAndSettle();
    expect(find.text('Навыков пока нет'), findsOneWidget);
    expect(find.byKey(const Key('skillPicker.manage')), findsOneWidget);
  });
}
