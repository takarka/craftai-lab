import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_providers.dart';
import '../assistant/assistant_providers.dart';
import 'domain/course_catalog.dart';
import 'domain/course_models.dart';
import 'domain/course_repository.dart';
import 'infrastructure/in_memory_course_repository.dart';
import 'infrastructure/persistent_course_repository.dart';

final courseRepositoryProvider = Provider<CourseRepository>((ref) {
  final db = ref.watch(storageDatabaseProvider);
  if (db == null) {
    return InMemoryCourseRepository();
  }
  final assistantRepo = ref.watch(assistantRepositoryProvider);
  return PersistentCourseRepository(
    database: db,
    assistantRepository: assistantRepo,
  );
});

final courseProgressListProvider =
    FutureProvider.family<List<LevelProgress>, String>((ref, ownerId) async {
      final repo = ref.watch(courseRepositoryProvider);
      return repo.getAllProgress(ownerId);
    });

final levelProgressProvider =
    FutureProvider.family<LevelProgress?, ({String ownerId, int levelId})>((
      ref,
      arg,
    ) async {
      final repo = ref.watch(courseRepositoryProvider);
      return repo.getLevelProgress(arg.ownerId, arg.levelId);
    });

final levelStatusProvider =
    FutureProvider.family<LevelStatus, ({String ownerId, int levelId})>((
      ref,
      arg,
    ) async {
      final repo = ref.watch(courseRepositoryProvider);
      return repo.getLevelStatus(arg.ownerId, arg.levelId);
    });

final overallCourseProgressProvider =
    FutureProvider.family<OverallCourseProgress, String>((ref, ownerId) async {
      final repo = ref.watch(courseRepositoryProvider);
      return repo.getOverallProgress(ownerId);
    });

final courseControllerProvider = Provider.family<CourseController, String>((
  ref,
  ownerId,
) {
  return CourseController(ref, ownerId);
});

class CourseController {
  CourseController(this._ref, this.ownerId);

  final Ref _ref;
  final String ownerId;

  CourseRepository get _repo => _ref.read(courseRepositoryProvider);

  Future<void> saveStep(
    int levelId,
    LessonStep step, {
    bool? practiceEvidenceMet,
  }) async {
    await _repo.saveCheckpoint(
      ownerId: ownerId,
      levelId: levelId,
      step: step.stepNumber,
      practiceEvidenceMet: practiceEvidenceMet,
    );
    _invalidate();
  }

  Future<bool> submitQuiz(
    int levelId,
    List<int> selectedAnswers, {
    double threshold = 0.66,
  }) async {
    final passed = await _repo.recordQuizAttempt(
      ownerId: ownerId,
      levelId: levelId,
      selectedAnswers: selectedAnswers,
      threshold: threshold,
    );
    _invalidate();
    return passed;
  }

  Future<void> completeLevel(int levelId) async {
    await _repo.completeLevel(ownerId: ownerId, levelId: levelId);
    _invalidate();
    // Invalidate assistant providers since skill was granted and version was committed
    _ref.invalidate(assistantConfigProvider(ownerId));
    _ref.invalidate(assistantVersionsProvider(ownerId));
    _ref.invalidate(completedCourseLevelsProvider(ownerId));
  }

  Future<void> resetCourse() async {
    await _repo.resetCourseProgress(ownerId);
    _invalidate();
    _ref.invalidate(completedCourseLevelsProvider(ownerId));
  }

  void _invalidate() {
    _ref.invalidate(courseProgressListProvider(ownerId));
    _ref.invalidate(overallCourseProgressProvider(ownerId));
    for (final lvl in CourseCatalog.levels) {
      _ref.invalidate(
        levelProgressProvider((ownerId: ownerId, levelId: lvl.id)),
      );
      _ref.invalidate(levelStatusProvider((ownerId: ownerId, levelId: lvl.id)));
    }
  }
}
