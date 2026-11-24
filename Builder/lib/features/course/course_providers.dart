import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_providers.dart';
import '../assistant/assistant_providers.dart';
import 'domain/course_access.dart';
import 'domain/course_catalog.dart';
import 'domain/course_models.dart';
import 'domain/course_repository.dart';
import 'domain/course_topic.dart';
import 'domain/transfer_review.dart';
import 'infrastructure/in_memory_course_repository.dart';
import 'infrastructure/persistent_course_repository.dart';
import 'transfer_review_providers.dart';

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
      final restoration = _localReview(ref, ownerId);
      final progress = await repo.getAllProgress(ownerId);
      final review = await restoration;
      if (review == null) return progress;
      return [
        for (final entry in progress)
          if (entry.levelId == CourseTopic.transfer.storageId)
            _restoreTransferProgress(entry, review)
          else
            entry,
      ];
    });

final levelProgressProvider =
    FutureProvider.family<LevelProgress?, ({String ownerId, int levelId})>((
      ref,
      arg,
    ) async {
      final repo = ref.watch(courseRepositoryProvider);
      if (arg.levelId != CourseTopic.transfer.storageId) {
        return repo.getLevelProgress(arg.ownerId, arg.levelId);
      }
      final restoration = _localReview(ref, arg.ownerId);
      final base = await repo.getLevelProgress(arg.ownerId, arg.levelId);
      final review = await restoration;
      if (base == null) return null;
      if (review != null) return _restoreTransferProgress(base, review);
      // A pre-upgrade self-check was not a completed review.
      return base.isCompleted
          ? base
          : base.copyWith(
              currentStep: base.currentStep > 2 ? 2 : base.currentStep,
              practiceEvidenceMet: false,
            );
    });

final levelStatusProvider =
    FutureProvider.family<LevelStatus, ({String ownerId, int levelId})>((
      ref,
      arg,
    ) async {
      final repo = ref.watch(courseRepositoryProvider);
      if (arg.levelId != CourseTopic.transfer.storageId) {
        return repo.getLevelStatus(arg.ownerId, arg.levelId);
      }
      final progress = await ref.watch(
        courseProgressListProvider(arg.ownerId).future,
      );
      return CourseAccess.status(arg.levelId, progress);
    });

final overallCourseProgressProvider =
    FutureProvider.family<OverallCourseProgress, String>((ref, ownerId) async {
      final repo = ref.watch(courseRepositoryProvider);
      final restoration = _localReview(ref, ownerId);
      final base = await repo.getOverallProgress(ownerId);
      final review = await restoration;
      if (review == null) return base;
      final id = CourseTopic.transfer.storageId;
      final addCompletion =
          review.completed && !base.completedLevelIds.contains(id);
      return OverallCourseProgress(
        completedLevelsCount:
            base.completedLevelsCount + (addCompletion ? 1 : 0),
        totalActiveLevels: base.totalActiveLevels,
        activeLevelId: review.completed ? base.activeLevelId : id,
        activeStep: review.completed
            ? base.activeStep
            : LessonStep.fromNumber(review.step),
        completedLevelIds: {
          ...base.completedLevelIds,
          if (review.completed) id,
        },
      );
    });

Future<TransferReview?> _localReview(Ref ref, String ownerId) async {
  try {
    return await ref.watch(transferReviewProvider(ownerId).future);
  } catch (_) {
    // Older course screens still work when local review storage is unavailable.
    return null;
  }
}

LevelProgress _restoreTransferProgress(
  LevelProgress base,
  TransferReview review,
) {
  return base.copyWith(
    currentStep: review.secondReviewed
        ? review.step
        : LessonStep.practice.stepNumber,
    practiceEvidenceMet: review.secondReviewed,
    isCompleted: base.isCompleted || review.completed,
  );
}

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
    if (levelId == CourseTopic.transfer.storageId) {
      await _updateReview((review) => review.copyWith(step: step.stepNumber));
    }
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
    if (levelId == CourseTopic.transfer.storageId) {
      await _updateReview((review) => review.copyWith(completed: true));
    }
    _invalidate();
    // Invalidate assistant providers since skill was granted and version was committed
    _ref.invalidate(assistantConfigProvider(ownerId));
    _ref.invalidate(assistantVersionsProvider(ownerId));
    _ref.invalidate(completedCourseLevelsProvider(ownerId));
  }

  Future<void> resetCourse() async {
    final review = transferReviewProvider(ownerId);
    if (_ref.read(review).asData?.value != null) {
      await _ref.read(review.notifier).change((_) => null);
    }
    await _repo.resetCourseProgress(ownerId);
    _invalidate();
    _ref.invalidate(completedCourseLevelsProvider(ownerId));
  }

  Future<void> _updateReview(
    TransferReview Function(TransferReview) edit,
  ) async {
    final review = transferReviewProvider(ownerId);
    if (_ref.read(review).asData?.value != null) {
      await _ref
          .read(review.notifier)
          .change((current) => current == null ? null : edit(current));
    }
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
