import 'package:builder/features/course/domain/course_access.dart';
import 'package:builder/features/course/domain/course_catalog.dart';
import 'package:builder/features/course/domain/course_models.dart';
import 'package:builder/features/course/domain/course_topic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seven current lessons keep the six published progress IDs', () {
    const ids = [1, 2, 10, 3, 4, 5, 12];
    expect(CourseTopic.enabledSequence.map((topic) => topic.storageId), ids);
    for (final locale in ['ru', 'kk']) {
      final lessons = CourseCatalog.getLevels(locale: locale);
      expect(lessons.map((lesson) => lesson.id), ids);
      expect(lessons.map((lesson) => lesson.displayOrder), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      ]);
      for (final lesson in lessons) {
        expect(lesson.ideaText.length, greaterThan(300));
        expect(lesson.ideaExampleTemplate, isNotEmpty);
        expect(lesson.practiceExpectedAnswer, isNotEmpty);
        expect(lesson.underTheHoodExplanation, isNotEmpty);
        expect(lesson.quizQuestions, hasLength(3));
        for (final question in lesson.quizQuestions) {
          expect(
            question.correctIndex,
            inInclusiveRange(0, question.options.length - 1),
          );
        }
      }
      final transfer = CourseCatalog.getLevel(12, locale: locale)!;
      expect(transfer.contentId, 'course.topic.transfer');
      expect(transfer.practiceDefaultInput, contains('3/8'));
      expect(transfer.practiceDefaultInput, contains('5/8'));
    }
  });

  test('capstone unlocks after tools, not from a retired progress ID', () {
    LevelProgress completed(int id) => LevelProgress(
      ownerId: 'teacher',
      levelId: id,
      contentVersion: '1.2.0',
      currentStep: 5,
      completedCheckpoints: const [1, 2, 3, 4, 5],
      attemptsCount: 1,
      isCompleted: true,
      updatedAtUtc: DateTime.utc(2026),
    );

    expect(CourseAccess.status(12, [completed(11)]), LevelStatus.locked);
    expect(
      CourseAccess.status(12, [completed(5), completed(11)]),
      LevelStatus.available,
    );
    expect(CourseTopic.tools.next, CourseTopic.transfer);
    expect(CourseTopic.transfer.next, isNull);
  });
}
