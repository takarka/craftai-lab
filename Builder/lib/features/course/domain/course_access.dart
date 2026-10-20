import 'course_models.dart';
import 'course_topic.dart';

abstract final class CourseAccess {
  static CourseTopic? prerequisite(int id) =>
      CourseTopic.fromStorageId(id).prerequisite;

  static LevelStatus status(int id, List<LevelProgress> progress) {
    if (!CourseTopic.isEnabledStorageId(id)) return LevelStatus.comingSoon;
    final current = progress.where((p) => p.levelId == id).firstOrNull;
    if (current?.isCompleted == true) return LevelStatus.completed;
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
