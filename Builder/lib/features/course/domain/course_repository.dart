import 'course_models.dart';

abstract interface class CourseRepository {
  /// Returns all progress records for [ownerId].
  Future<List<LevelProgress>> getAllProgress(String ownerId);

  /// Returns progress record for a specific [levelId].
  Future<LevelProgress?> getLevelProgress(String ownerId, int levelId);

  /// Computes current level status based on completion of previous levels.
  Future<LevelStatus> getLevelStatus(String ownerId, int levelId);

  /// Calculates aggregated course progress (e.g. 2 of 5 levels completed).
  Future<OverallCourseProgress> getOverallProgress(String ownerId);

  /// Saves checkpoint for [levelId] at [step] (1..5) with optional [practiceEvidenceMet].
  Future<void> saveCheckpoint({
    required String ownerId,
    required int levelId,
    required int step,
    bool? practiceEvidenceMet,
  });

  /// Records quiz attempt with [selectedAnswers] and checks if it passes [threshold].
  /// Returns `true` if passed, `false` otherwise.
  Future<bool> recordQuizAttempt({
    required String ownerId,
    required int levelId,
    required List<int> selectedAnswers,
    required double threshold,
  });

  /// Atomically completes [levelId], unblocks next level, grants skills and commits version.
  Future<void> completeLevel({
    required String ownerId,
    required int levelId,
  });

  /// Resets all course progress and quiz attempts for [ownerId].
  Future<void> resetCourseProgress(String ownerId);
}
