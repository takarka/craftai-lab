import '../domain/course_catalog.dart';
import '../domain/course_models.dart';
import '../domain/course_repository.dart';

final class InMemoryCourseRepository implements CourseRepository {
  final Map<String, Map<int, LevelProgress>> _progress = {};

  @override
  Future<List<LevelProgress>> getAllProgress(String ownerId) async {
    final userMap = _progress[ownerId] ?? const {};
    return CourseCatalog.levels.map((lvl) {
      if (userMap.containsKey(lvl.id)) {
        return userMap[lvl.id]!;
      }
      return LevelProgress(
        ownerId: ownerId,
        levelId: lvl.id,
        contentVersion: CourseCatalog.currentContentVersion,
        currentStep: 1,
        completedCheckpoints: const [],
        attemptsCount: 0,
        isCompleted: false,
        updatedAtUtc: DateTime.now().toUtc(),
        practiceEvidenceMet: false,
      );
    }).toList();
  }

  @override
  Future<LevelProgress?> getLevelProgress(String ownerId, int levelId) async {
    final all = await getAllProgress(ownerId);
    return all.firstWhere((p) => p.levelId == levelId);
  }

  @override
  Future<LevelStatus> getLevelStatus(String ownerId, int levelId) async {
    if (levelId > 5) return LevelStatus.comingSoon;

    final all = await getAllProgress(ownerId);
    final current = all.firstWhere(
      (p) => p.levelId == levelId,
      orElse: () => all.first,
    );

    if (current.isCompleted) return LevelStatus.completed;

    if (levelId == 1) {
      return current.currentStep > 1
          ? LevelStatus.inProgress
          : LevelStatus.available;
    }

    final prev = all.firstWhere(
      (p) => p.levelId == levelId - 1,
      orElse: () => all.first,
    );
    if (!prev.isCompleted) {
      return LevelStatus.locked;
    }

    return current.currentStep > 1
        ? LevelStatus.inProgress
        : LevelStatus.available;
  }

  @override
  Future<OverallCourseProgress> getOverallProgress(String ownerId) async {
    final all = await getAllProgress(ownerId);
    final completed = all
        .where((p) => p.levelId <= 5 && p.isCompleted)
        .map((p) => p.levelId)
        .toSet();

    int? activeLevelId;
    var activeStep = LessonStep.idea;

    for (int lvl = 1; lvl <= 5; lvl++) {
      if (!completed.contains(lvl)) {
        activeLevelId = lvl;
        final p = all.firstWhere((item) => item.levelId == lvl);
        activeStep = LessonStep.fromNumber(p.currentStep);
        break;
      }
    }

    return OverallCourseProgress(
      totalActiveLevels: 5,
      completedLevelsCount: completed.length,
      activeLevelId: activeLevelId,
      activeStep: activeStep,
      completedLevelIds: completed,
    );
  }

  @override
  Future<void> saveCheckpoint({
    required String ownerId,
    required int levelId,
    required int step,
    bool? practiceEvidenceMet,
  }) async {
    final userMap = _progress.putIfAbsent(ownerId, () => {});
    final current =
        userMap[levelId] ??
        LevelProgress(
          ownerId: ownerId,
          levelId: levelId,
          contentVersion: CourseCatalog.currentContentVersion,
          currentStep: 1,
          completedCheckpoints: const [],
          attemptsCount: 0,
          isCompleted: false,
          updatedAtUtc: DateTime.now().toUtc(),
          practiceEvidenceMet: false,
        );

    final checkpoints = List<int>.from(current.completedCheckpoints);
    if (!checkpoints.contains(step - 1) && step > 1) {
      checkpoints.add(step - 1);
    }
    if (practiceEvidenceMet == true && !checkpoints.contains(2)) {
      checkpoints.add(2);
    }
    checkpoints.sort();

    userMap[levelId] = LevelProgress(
      ownerId: ownerId,
      levelId: levelId,
      contentVersion: current.contentVersion,
      currentStep: current.isCompleted ? 5 : step.clamp(1, 5),
      completedCheckpoints: checkpoints,
      attemptsCount: current.attemptsCount,
      isCompleted: current.isCompleted,
      updatedAtUtc: DateTime.now().toUtc(),
      practiceEvidenceMet: checkpoints.contains(2) || current.isCompleted,
    );
  }

  @override
  Future<bool> recordQuizAttempt({
    required String ownerId,
    required int levelId,
    required List<int> selectedAnswers,
    required double threshold,
  }) async {
    final level = CourseCatalog.getLevel(levelId);
    if (level == null || level.quizQuestions.isEmpty) {
      return true;
    }

    int correct = 0;
    for (int i = 0; i < level.quizQuestions.length; i++) {
      if (i < selectedAnswers.length &&
          selectedAnswers[i] == level.quizQuestions[i].correctIndex) {
        correct++;
      }
    }

    final score = correct / level.quizQuestions.length;
    final passed = score >= threshold;

    final userMap = _progress.putIfAbsent(ownerId, () => {});
    final current =
        userMap[levelId] ??
        LevelProgress(
          ownerId: ownerId,
          levelId: levelId,
          contentVersion: CourseCatalog.currentContentVersion,
          currentStep: 1,
          completedCheckpoints: const [],
          attemptsCount: 0,
          isCompleted: false,
          updatedAtUtc: DateTime.now().toUtc(),
          practiceEvidenceMet: false,
        );

    final checkpoints = List<int>.from(current.completedCheckpoints);
    if (passed && !checkpoints.contains(4)) {
      checkpoints.add(4);
      checkpoints.sort();
    }

    userMap[levelId] = LevelProgress(
      ownerId: ownerId,
      levelId: levelId,
      contentVersion: current.contentVersion,
      currentStep: passed ? 5 : 4,
      completedCheckpoints: checkpoints,
      attemptsCount: current.attemptsCount + 1,
      isCompleted: current.isCompleted,
      updatedAtUtc: DateTime.now().toUtc(),
      practiceEvidenceMet: checkpoints.contains(2) || current.isCompleted,
    );

    return passed;
  }

  @override
  Future<void> completeLevel({
    required String ownerId,
    required int levelId,
  }) async {
    final level = CourseCatalog.getLevel(levelId);
    if (level == null) throw ArgumentError.value(levelId, 'levelId');
    if (level.comingSoon) throw StateError('Уровень ещё недоступен');
    final userMap = _progress.putIfAbsent(ownerId, () => {});
    final current =
        userMap[levelId] ??
        LevelProgress(
          ownerId: ownerId,
          levelId: levelId,
          contentVersion: CourseCatalog.currentContentVersion,
          currentStep: 1,
          completedCheckpoints: const [],
          attemptsCount: 0,
          isCompleted: false,
          updatedAtUtc: DateTime.now().toUtc(),
          practiceEvidenceMet: false,
        );

    final checkpoints = List<int>.from(current.completedCheckpoints);
    for (int i = 1; i <= 5; i++) {
      if (!checkpoints.contains(i)) checkpoints.add(i);
    }
    checkpoints.sort();

    userMap[levelId] = LevelProgress(
      ownerId: ownerId,
      levelId: levelId,
      contentVersion: current.contentVersion,
      currentStep: 5,
      completedCheckpoints: checkpoints,
      attemptsCount: current.attemptsCount,
      isCompleted: true,
      updatedAtUtc: DateTime.now().toUtc(),
      practiceEvidenceMet: true,
    );
  }

  @override
  Future<void> resetCourseProgress(String ownerId) async {
    _progress.remove(ownerId);
  }
}
