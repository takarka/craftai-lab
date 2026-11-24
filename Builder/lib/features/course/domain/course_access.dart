import 'course_models.dart';
import 'course_topic.dart';

abstract final class CourseAccess {
  static CourseTopic? prerequisite(int id) =>
      CourseTopic.fromStorageId(id).prerequisite;

  static LevelStatus status(int id, List<LevelProgress> progress) {
    if (!CourseTopic.isEnabledStorageId(id)) return LevelStatus.comingSoon;
    final current = progress.where((p) => p.levelId == id).firstOrNull;
    if (current?.isCompleted == true) return LevelStatus.completed;
    // A locally saved transfer exercise is proof that this user previously
    // reached the capstone, even if the rest of the web course cache restarted.
    if (id == CourseTopic.transfer.storageId &&
        ((current?.currentStep ?? 1) > 1 || current?.practiceEvidenceMet == true)) {
      return LevelStatus.inProgress;
    }
    final previous = prerequisite(id);
    if (previous != null &&
        !progress.any(
          (p) => p.levelId == previous.storageId && p.isCompleted,
        )) {
      return LevelStatus.locked;
    }
    return (current?.currentStep ?? 1) > 1
        ? LevelStatus.inProgress
        : LevelStatus.available;
  }
}
