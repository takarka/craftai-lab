import 'package:builder/features/chat/domain/chat_message.dart';
import 'package:builder/features/skills/domain/skill_preparation.dart';
import 'package:builder/features/skills/domain/skill_practice_evidence.dart';
import 'package:builder/features/skills/domain/skill_scenario.dart';
import 'package:builder/features/skills/domain/skill_templates.dart';
import 'package:flutter_test/flutter_test.dart';

final original = SkillTemplates.forLocale().first;
SkillScenario changed({bool nameOnly = false}) => SkillScenario.fromJson({
  ...original.toJson(),
  'revision': 2,
  'name': 'Мой навык',
  if (!nameOnly)
    'quality_criteria': [
      ...original.qualityCriteria,
      'Объясни критерий оценивания каждого задания',
    ],
});

List<ChatMessage> run(
  SkillScenario skill,
  String topic, {
  String owner = 'alice',
  MessageStatus status = MessageStatus.completed,
  String answer = 'Задания и критерии',
}) => [
  ChatMessage(
    id: 'u-$topic',
    conversationId: 'conversation',
    ownerId: owner,
    role: MessageRole.user,
    content: SkillPreparation.prepare(skill, {
      'Тема': topic,
      'Класс': '5',
    }).userPrompt!,
    status: MessageStatus.completed,
    createdAtUtc: DateTime.utc(2026),
  ),
  ChatMessage(
    id: 'a-$topic',
    conversationId: 'conversation',
    ownerId: owner,
    role: MessageRole.assistant,
    content: answer,
    status: status,
    createdAtUtc: DateTime.utc(2026),
  ),
];

void main() {
  test(
    'Two distinct completed inputs plus a run of improved saved criteria satisfy practice',
    () {
      final improved = changed();
      expect(
        SkillPracticeEvidence.isMet(
          'alice',
          [improved],
          [run(original, 'Дроби'), run(improved, 'Уравнения')],
        ),
        isTrue,
      );
      expect(
        SkillPracticeEvidence.isMet('alice', [], [
          run(original, 'Дроби'),
          run(improved, 'Уравнения'),
        ]),
        isFalse,
      );
    },
  );
  test(
    'Creating, renaming or only editing without running does not satisfy practice',
    () {
      expect(SkillPracticeEvidence.isMet('alice', [original], []), isFalse);
      expect(
        SkillPracticeEvidence.isMet(
          'alice',
          [changed(nameOnly: true)],
          [run(original, 'Дроби'), run(changed(nameOnly: true), 'Уравнения')],
        ),
        isFalse,
      );
      expect(
        SkillPracticeEvidence.isMet(
          'alice',
          [changed()],
          [run(original, 'Дроби'), run(original, 'Уравнения')],
        ),
        isFalse,
      );
    },
  );
  test(
    'Repeated same inputs and unsuccessful replies do not satisfy practice',
    () {
      expect(
        SkillPracticeEvidence.isMet(
          'alice',
          [changed()],
          [run(original, 'Дроби'), run(changed(), 'Дроби')],
        ),
        isFalse,
      );
      for (final status in [
        MessageStatus.error,
        MessageStatus.interrupted,
        MessageStatus.streaming,
        MessageStatus.pending,
      ]) {
        expect(
          SkillPracticeEvidence.isMet(
            'alice',
            [changed()],
            [
              run(original, 'Дроби'),
              run(changed(), 'Уравнения', status: status),
            ],
          ),
          isFalse,
        );
      }
      expect(
        SkillPracticeEvidence.isMet(
          'alice',
          [changed()],
          [run(original, 'Дроби'), run(changed(), 'Уравнения', answer: '')],
        ),
        isFalse,
      );
    },
  );
  test('Another owner, conversation or skill cannot supply evidence', () {
    expect(
      SkillPracticeEvidence.isMet(
        'alice',
        [changed()],
        [run(original, 'Дроби'), run(changed(), 'Уравнения', owner: 'bob')],
      ),
      isFalse,
    );
    final other = SkillScenario.fromJson({
      ...changed().toJson(),
      'id': 'another',
    });
    expect(
      SkillPracticeEvidence.isMet(
        'alice',
        [changed()],
        [run(original, 'Дроби'), run(other, 'Уравнения')],
      ),
      isFalse,
    );
    final mixed = run(changed(), 'Уравнения');
    expect(
      SkillPracticeEvidence.isMet(
        'alice',
        [changed()],
        [
          run(original, 'Дроби'),
          [mixed.first, run(changed(), 'Уравнения', owner: 'bob').last],
        ],
      ),
      isFalse,
    );
  });
}
