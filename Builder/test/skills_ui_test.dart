import 'package:builder/features/skills/domain/skill_scenario.dart';
import 'package:builder/features/skills/domain/skill_templates.dart';
import 'package:builder/features/skills/domain/skills_repository.dart';
import 'package:builder/features/skills/presentation/skills_page.dart';
import 'package:builder/features/skills/skills_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/features/assistant/presentation/assistant_chat_page.dart';
import 'package:builder/features/chat/chat_providers.dart';
import 'package:builder/features/chat/domain/conversation.dart';
import 'package:builder/features/policy/policy_providers.dart';
import 'package:builder/features/policy/infrastructure/persistent_policy_repository.dart';
import 'package:builder/features/skills/domain/skill_preparation.dart';
import 'package:builder/features/skills/presentation/skill_request_summary.dart';

class _Repository implements SkillsRepository {
  SkillScenario? saved;
  String? owner;
  @override
  Future<List<SkillScenario>> getSkills(String ownerId) async =>
      saved == null ? [] : [saved!];
  @override
  Future<void> saveSkill(String ownerId, SkillScenario skill) async {
    owner = ownerId;
    saved = skill;
  }

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

Widget _app(Widget page, {_Repository? repository, String locale = 'ru'}) =>
    ProviderScope(
      overrides: [
        if (repository != null)
          skillsRepositoryProvider.overrideWithValue(repository),
        skillsListProvider('alice').overrideWith((ref) async => []),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: const [Locale('ru'), Locale('kk')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: page,
      ),
    );

void main() {
  test(
    'Persisted request summary is readable and ordinary JSON stays intact',
    () {
      final skill = SkillTemplates.forLocale().first;
      final prompt = SkillPreparation.prepare(skill, {
        'Тема': 'Дроби',
        'Класс': '5',
      }).userPrompt!;
      final summary = skillRequestSummary(prompt, isKk: false);
      expect(summary, contains('Тема: Дроби'));
      expect(summary, contains(skill.steps.first));
      expect(summary, isNot(contains('builder_skill_request')));
      expect(skillRequestSummary('{"value":1}', isKk: false), '{"value":1}');
      expect(
        skillRequestSummary('{"builder_skill_request":1}', isKk: false),
        '{"builder_skill_request":1}',
      );
    },
  );

  for (final (consent, stale) in [
    (false, false),
    (true, false),
    (true, true),
  ]) {
    testWidgets('Skill run respects D02 consent: $consent; deleted: $stale', (
      tester,
    ) async {
      final skill = SkillTemplates.forLocale().first;
      final repository = _Repository()..saved = skill;
      final chat = _Chat();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            skillsRepositoryProvider.overrideWithValue(repository),
            chatSessionProvider('alice').overrideWith(() => chat),
            policyRepositoryProvider.overrideWithValue(
              InMemoryPolicyRepository(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('ru'),
            home: AssistantChatPage(
              ownerId: 'alice',
              skillRun: SkillRunDraft(
                skill: skill,
                inputs: {'Тема': 'Дроби', 'Класс': '5'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(chat.sent, isEmpty);
      await tester.tap(find.byKey(const Key('skill.send')));
      await tester.pumpAndSettle();
      expect(chat.sent, isEmpty);
      final button = find.byKey(Key(consent ? 'd02.understand' : 'd02.notNow'));
      if (stale) repository.saved = null;
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      if (consent && !stale) {
        expect(chat.sent, hasLength(1));
        expect(jsonDecode(chat.sent.single)['inputs'], {
          'Тема': 'Дроби',
          'Класс': '5',
        });
      } else {
        expect(chat.sent, isEmpty);
        expect(find.byKey(const Key('skill.send')), findsOneWidget);
      }
    });
  }
  testWidgets('Empty list offers all four templates in RU and KK', (
    tester,
  ) async {
    for (final language in ['ru', 'kk']) {
      await tester.pumpWidget(
        _app(const SkillsPage(ownerId: 'alice'), locale: language),
      );
      await tester.pumpAndSettle();
      for (final template in SkillTemplates.forLocale(isKk: language == 'kk')) {
        expect(find.text(template.name), findsOneWidget);
      }
      expect(find.byKey(const Key('skills.add')), findsOneWidget);
    }
  });

  testWidgets('Editor refuses blank fields and duplicate input names', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _Repository();
    await tester.pumpWidget(
      _app(const SkillEditorPage(ownerId: 'alice'), repository: repository),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('skill.save')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill.save')));
    await tester.pumpAndSettle();
    expect(repository.saved, isNull);
    expect(find.text('Заполните поле'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const Key('skill.field.2')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('skill.field.2')),
      'Тема\nТема',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('skill.save')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill.save')));
    await tester.pumpAndSettle();
    expect(repository.saved, isNull);
  });

  testWidgets('Template creates a distinct scenario for the current owner', (
    tester,
  ) async {
    final repository = _Repository();
    final template = SkillTemplates.forLocale().first;
    await tester.pumpWidget(
      _app(
        SkillEditorPage(ownerId: 'alice', skill: template, fromTemplate: true),
        repository: repository,
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('skill.save')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill.save')));
    await tester.pumpAndSettle();
    expect(repository.owner, 'alice');
    expect(repository.saved!.id, isNot(template.id));
    expect(repository.saved!.steps, template.steps);
    expect(repository.saved!.sources, template.sources);
  });

  testWidgets(
    'Manual run asks for missing required inputs before opening chat',
    (tester) async {
      await tester.pumpWidget(
        _app(
          SkillDetailsPage(
            ownerId: 'alice',
            skill: SkillTemplates.forLocale().first,
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('skill.prepare')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('skill.prepare')));
      await tester.pumpAndSettle();
      expect(find.text('Укажите эти данные'), findsNWidgets(2));
      expect(find.byKey(const Key('skill.send')), findsNothing);
    },
  );
}
