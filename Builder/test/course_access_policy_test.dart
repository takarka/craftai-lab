import 'package:builder/features/course/domain/course_access.dart';
import 'package:builder/features/course/domain/course_models.dart';
import 'package:flutter_test/flutter_test.dart';

LevelProgress done(int id, String version) => LevelProgress(
  ownerId: 'alice',
  levelId: id,
  contentVersion: version,
  currentStep: 5,
  completedCheckpoints: const [1, 2, 3, 4, 5],
  attemptsCount: 1,
  isCompleted: true,
  updatedAtUtc: DateTime.utc(2026),
);

void main() {
  test('New learners pass Skills before Knowledge', () {
    final progress = [done(1, '1.2.0'), done(2, '1.2.0')];
    expect(CourseAccess.status(10, progress), LevelStatus.available);
    expect(CourseAccess.status(3, progress), LevelStatus.locked);
    expect(
      CourseAccess.status(3, [...progress, done(10, '1.2.0')]),
      LevelStatus.available,
    );
    expect(CourseAccess.status(11, progress), LevelStatus.comingSoon);
  });
  test(
    'All accounts use the same order and completed topics remain completed',
    () {
      for (final version in ['1.0.0', '1.1.0']) {
        final progress = [done(1, version), done(2, version)];
        expect(CourseAccess.status(3, progress), LevelStatus.locked);
        expect(CourseAccess.status(10, progress), LevelStatus.available);
        expect(
          CourseAccess.status(4, [...progress, done(4, version)]),
          LevelStatus.completed,
        );
      }
      expect(CourseAccess.status(3, []), LevelStatus.locked);
    },
  );
}
