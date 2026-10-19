import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../../assistant/domain/assistant_repository.dart';
import '../domain/course_access.dart';
import '../domain/course_catalog.dart';
import '../domain/course_models.dart';
import '../domain/course_topic.dart';
import '../domain/course_repository.dart';

class PersistentCourseRepository implements CourseRepository {
  PersistentCourseRepository({
    required this.database,
    this.assistantRepository,
  });

  final StorageDatabase database;
  final AssistantRepository? assistantRepository;

  Future<void> _ensureOpen() async {
    if (!database.isOpen) {
      await database.open();
    }
  }

  @override
  Future<List<LevelProgress>> getAllProgress(String ownerId) async {
    await _ensureOpen();

    final rows = await database.db.query(
      StorageSchemaV1.tableCourseProgress,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'CAST(level_id AS INTEGER) ASC',
    );

    final map = <int, LevelProgress>{};
    for (final r in rows) {
      final lvlId = int.tryParse(r['level_id'] as String) ?? 0;
      if (lvlId > 0) {
        final checkpoints =
            (jsonDecode(r['completed_checkpoints_json'] as String? ?? '[]')
                    as List<dynamic>)
                .map((e) => e as int)
                .toList();
        final isCompleted = (r['is_completed'] as int? ?? 0) == 1;
        final currentStep = (r['current_step'] as int? ?? 1).clamp(1, 5);
        final practiceEvidence = checkpoints.contains(2) || isCompleted;

        map[lvlId] = LevelProgress(
          ownerId: ownerId,
          levelId: lvlId,
          contentVersion:
              r['content_version'] as String? ??
              CourseCatalog.currentContentVersion,
          currentStep: isCompleted ? 5 : currentStep,
          completedCheckpoints: checkpoints,
          attemptsCount: r['attempts_count'] as int? ?? 0,
          isCompleted: isCompleted,
          updatedAtUtc:
              DateTime.tryParse(r['updated_at_utc'] as String? ?? '') ??
              DateTime.now().toUtc(),
          practiceEvidenceMet: practiceEvidence,
        );
      }
    }

    // Keep stored keys unchanged; the catalog supplies the current display order.
    return CourseCatalog.levels.map((lvl) {
      if (map.containsKey(lvl.id)) {
        return map[lvl.id]!;
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
    await _ensureOpen();

    final rows = await database.db.query(
      StorageSchemaV1.tableCourseProgress,
      where: 'owner_id = ? AND level_id = ?',
      whereArgs: [ownerId, levelId.toString()],
    );

    if (rows.isEmpty) {
      return LevelProgress(
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
    }

    final r = rows.first;
    final checkpoints =
        (jsonDecode(r['completed_checkpoints_json'] as String? ?? '[]')
                as List<dynamic>)
            .map((e) => e as int)
            .toList();
    final isCompleted = (r['is_completed'] as int? ?? 0) == 1;
    final currentStep = (r['current_step'] as int? ?? 1).clamp(1, 5);

    return LevelProgress(
      ownerId: ownerId,
      levelId: levelId,
      contentVersion:
          r['content_version'] as String? ??
          CourseCatalog.currentContentVersion,
      currentStep: isCompleted ? 5 : currentStep,
      completedCheckpoints: checkpoints,
      attemptsCount: r['attempts_count'] as int? ?? 0,
      isCompleted: isCompleted,
      updatedAtUtc:
          DateTime.tryParse(r['updated_at_utc'] as String? ?? '') ??
          DateTime.now().toUtc(),
      practiceEvidenceMet: checkpoints.contains(2) || isCompleted,
    );
  }

  @override
  Future<LevelStatus> getLevelStatus(String ownerId, int levelId) async {
    return CourseAccess.status(levelId, await getAllProgress(ownerId));
  }

  @override
  Future<OverallCourseProgress> getOverallProgress(String ownerId) async {
    final all = await getAllProgress(ownerId);
    final completed = all
        .where(
          (p) => CourseTopic.isEnabledStorageId(p.levelId) && p.isCompleted,
        )
        .map((p) => p.levelId)
        .toSet();

    // Find active level for resume
    int? activeLevelId;
    var activeStep = LessonStep.idea;

    for (final topic in CourseTopic.enabledSequence) {
      final i = topic.storageId;
      final p = all.firstWhere((item) => item.levelId == i);
      if (!p.isCompleted) {
        activeLevelId = i;
        activeStep = LessonStep.fromNumber(p.currentStep);
        break;
      }
    }

    return OverallCourseProgress(
      completedLevelsCount: completed.length,
      totalActiveLevels: CourseTopic.enabledSequence.length,
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
    await _ensureOpen();

    final rows = await database.db.query(
      StorageSchemaV1.tableCourseProgress,
      where: 'owner_id = ? AND level_id = ?',
      whereArgs: [ownerId, levelId.toString()],
    );

    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final List<int> checkpoints = rows.isNotEmpty
        ? (jsonDecode(
                    rows.first['completed_checkpoints_json'] as String? ?? '[]',
                  )
                  as List<dynamic>)
              .map((e) => e as int)
              .toList()
        : <int>[];

    // If step 1 completed, record it
    if (!checkpoints.contains(step - 1) && step > 1) {
      checkpoints.add(step - 1);
    }
    if (practiceEvidenceMet == true && !checkpoints.contains(2)) {
      checkpoints.add(2);
    }

    checkpoints.sort();

    final isAlreadyCompleted =
        rows.isNotEmpty && (rows.first['is_completed'] as int? ?? 0) == 1;

    await database.db.insert(StorageSchemaV1.tableCourseProgress, {
      'owner_id': ownerId,
      'level_id': levelId.toString(),
      'content_version': rows.isNotEmpty
          ? rows.first['content_version']
          : CourseCatalog.currentContentVersion,
      'current_step': isAlreadyCompleted ? 5 : step.clamp(1, 5),
      'completed_checkpoints_json': jsonEncode(checkpoints),
      'attempts_count': rows.isNotEmpty
          ? (rows.first['attempts_count'] as int? ?? 0)
          : 0,
      'is_completed': isAlreadyCompleted ? 1 : 0,
      'updated_at_utc': nowUtc,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<bool> recordQuizAttempt({
    required String ownerId,
    required int levelId,
    required List<int> selectedAnswers,
    required double threshold,
  }) async {
    await _ensureOpen();

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
    final nowUtc = DateTime.now().toUtc().toIso8601String();

    // 1. Record in quiz_attempts
    final attemptId =
        '${ownerId}_${levelId}_${DateTime.now().millisecondsSinceEpoch}';
    await database.db.insert(StorageSchemaV1.tableQuizAttempts, {
      'id': attemptId,
      'owner_id': ownerId,
      'level_id': levelId.toString(),
      'question_revisions_json': jsonEncode(
        level.quizQuestions.map((q) => q.id).toList(),
      ),
      'answers_json': jsonEncode(selectedAnswers),
      'score': score,
      'threshold': threshold,
      'completed_at_utc': nowUtc,
    });

    // 2. Increment attempts_count in course_progress
    final progressRows = await database.db.query(
      StorageSchemaV1.tableCourseProgress,
      where: 'owner_id = ? AND level_id = ?',
      whereArgs: [ownerId, levelId.toString()],
    );

    final currentAttempts = progressRows.isNotEmpty
        ? (progressRows.first['attempts_count'] as int? ?? 0)
        : 0;
    final checkpoints = progressRows.isNotEmpty
        ? (jsonDecode(
                    progressRows.first['completed_checkpoints_json']
                            as String? ??
                        '[]',
                  )
                  as List<dynamic>)
              .map((e) => e as int)
              .toList()
        : <int>[];

    if (passed && !checkpoints.contains(4)) {
      checkpoints.add(4);
      checkpoints.sort();
    }

    final isAlreadyCompleted =
        progressRows.isNotEmpty &&
        (progressRows.first['is_completed'] as int? ?? 0) == 1;

    await database.db.insert(StorageSchemaV1.tableCourseProgress, {
      'owner_id': ownerId,
      'level_id': levelId.toString(),
      'content_version': progressRows.isNotEmpty
          ? progressRows.first['content_version']
          : CourseCatalog.currentContentVersion,
      'current_step': passed ? 5 : 4,
      'completed_checkpoints_json': jsonEncode(checkpoints),
      'attempts_count': currentAttempts + 1,
      'is_completed': isAlreadyCompleted ? 1 : 0,
      'updated_at_utc': nowUtc,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    return passed;
  }

  @override
  Future<void> completeLevel({
    required String ownerId,
    required int levelId,
  }) async {
    await _ensureOpen();

    final level = CourseCatalog.getLevel(levelId);
    if (level == null) {
      throw ArgumentError('Уровень $levelId не найден в каталоге курса');
    }
    if (level.comingSoon) {
      throw StateError('Уровень ещё недоступен');
    }

    // 1. Check if level is already completed (F10-11: Idempotency, no repeated grants or version spam)
    final existingRows = await database.db.query(
      StorageSchemaV1.tableCourseProgress,
      where: 'owner_id = ? AND level_id = ?',
      whereArgs: [ownerId, levelId.toString()],
    );

    final wasAlreadyCompleted =
        existingRows.isNotEmpty &&
        (existingRows.first['is_completed'] as int? ?? 0) == 1;

    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final checkpoints = existingRows.isNotEmpty
        ? (jsonDecode(
                    existingRows.first['completed_checkpoints_json']
                            as String? ??
                        '[]',
                  )
                  as List<dynamic>)
              .map((e) => e as int)
              .toList()
        : <int>[];

    for (int step = 1; step <= 5; step++) {
      if (!checkpoints.contains(step)) checkpoints.add(step);
    }
    checkpoints.sort();

    await database.db.insert(StorageSchemaV1.tableCourseProgress, {
      'owner_id': ownerId,
      'level_id': levelId.toString(),
      'content_version': existingRows.isNotEmpty
          ? existingRows.first['content_version']
          : CourseCatalog.currentContentVersion,
      'current_step': 5,
      'completed_checkpoints_json': jsonEncode(checkpoints),
      'attempts_count': existingRows.isNotEmpty
          ? (existingRows.first['attempts_count'] as int? ?? 1)
          : 1,
      'is_completed': 1,
      'updated_at_utc': nowUtc,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // 2. If it was already completed previously, do not duplicate grants or commit another version
    if (wasAlreadyCompleted) {
      return;
    }

    // 3. Atomically grant skill and commit version in assistant configuration (F10-09)
    if (assistantRepository != null) {
      final config = await assistantRepository!.getConfiguration(ownerId);
      if (config != null) {
        final updatedSkills = Set<String>.from(config.enabledSkills);
        if (level.targetSkillId != null && !level.targetSkillId!.comingSoon) {
          updatedSkills.add(level.targetSkillId!.id);
        }

        await assistantRepository!.commitChange(
          ownerId: ownerId,
          name: config.name,
          selectedCategory: config.selectedCategory,
          enabledSkills: updatedSkills,
          systemRules: config.systemRules,
          reason: 'Завершение уровня $levelId: ${level.title}',
        );
      }
    }
  }

  @override
  Future<void> resetCourseProgress(String ownerId) async {
    await _ensureOpen();

    await database.db.delete(
      StorageSchemaV1.tableCourseProgress,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );

    await database.db.delete(
      StorageSchemaV1.tableQuizAttempts,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
  }
}
