import 'dart:io';

import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/assistant/domain/assistant_config.dart';
import 'package:builder/features/course/domain/course_catalog.dart';
import 'package:builder/features/course/domain/course_models.dart';
import 'package:builder/features/course/domain/course_topic.dart';
import 'package:builder/features/course/infrastructure/in_memory_course_repository.dart';
import 'package:builder/features/course/infrastructure/persistent_course_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('Both locales expose eleven ordered topics with stable legacy keys', () {
    for (final locale in ['ru', 'kk']) {
      final levels = CourseCatalog.getLevels(locale: locale);
      expect(
        levels.map((l) => l.displayOrder),
        List.generate(11, (i) => i + 1),
      );
      expect(levels.map((l) => l.contentId).toSet().length, 11);
      final knowledge = CourseCatalog.getLevelByContentId(
        'course.topic.knowledge',
        locale: locale,
      )!;
      expect(knowledge.id, 3);
      expect(knowledge.displayOrder, 4);
      expect(knowledge.targetSkillId, AssistantSkillId.knowledge);
      expect(CourseCatalog.getLevel(10)!.comingSoon, isFalse);
      expect(CourseCatalog.getLevel(11)!.comingSoon, isTrue);
    }
    expect(AssistantSkillId.knowledge.level, 3);
    expect(AssistantSkillId.knowledge.displayLevel, 4);
    expect(AssistantSkillId.tools.displayLevel, 6);
  });

  test(
    'New learner passes topics in the visible order, Skills third',
    () async {
      final repository = InMemoryCourseRepository();
      Future<List<LevelStatus>> statuses() async => [
        for (final id in [1, 2, 10, 3, 4, 5])
          await repository.getLevelStatus('new', id),
      ];

      expect(await statuses(), [
        LevelStatus.available,
        LevelStatus.locked,
        LevelStatus.locked,
        LevelStatus.locked,
        LevelStatus.locked,
        LevelStatus.locked,
      ]);
      await repository.completeLevel(ownerId: 'new', levelId: 1);
      await repository.completeLevel(ownerId: 'new', levelId: 2);
      expect((await statuses()).sublist(2, 4), [
        LevelStatus.available,
        LevelStatus.locked,
      ]);
      expect((await repository.getOverallProgress('new')).activeLevelId, 10);
      await repository.completeLevel(ownerId: 'new', levelId: 10);
      expect(await repository.getLevelStatus('new', 3), LevelStatus.available);
      expect((await repository.getOverallProgress('new')).activeLevelId, 3);
      expect((await repository.getOverallProgress('new')).totalActiveLevels, 6);
    },
  );

  group('Upgrade from stored nine-level progress', () {
    late Directory temp;
    late StorageDatabase database;
    late PersistentCourseRepository repository;

    setUp(() async {
      sqfliteFfiInit();
      temp = await Directory.systemTemp.createTemp('curriculum_upgrade_');
      database = StorageDatabase(
        databasePath: p.join(temp.path, 'course.db'),
        databaseFactory: databaseFactoryFfi,
      );
      await database.open();
      final workspace = WorkspaceStorageService(
        database: database,
        keyStorage: InMemorySecureKeyStorage(),
        installationId: 'upgrade-test',
      );
      for (final owner in ['existing', 'other']) {
        await workspace.openWorkspace(ownerId: owner);
      }
      for (var id = 1; id <= 5; id++) {
        await database.db.insert(StorageSchemaV1.tableCourseProgress, {
          'owner_id': 'existing',
          'level_id': '$id',
          'content_version': '1.0.0',
          'current_step': 5,
          'completed_checkpoints_json': '[1,2,3,4,5]',
          'attempts_count': 2,
          'is_completed': 1,
          'updated_at_utc': '2026-10-18T12:00:00.000Z',
        });
      }
      repository = PersistentCourseRepository(database: database);
    });

    tearDown(() async {
      await database.close();
      await temp.delete(recursive: true);
    });

    test(
      'Reset rolls back progress deletion when quiz cleanup fails',
      () async {
        await database.db.execute('''
        CREATE TRIGGER fail_quiz_cleanup BEFORE DELETE ON quiz_attempts
        BEGIN SELECT RAISE(ABORT, 'simulated cleanup failure'); END;
      ''');
        await repository.recordQuizAttempt(
          ownerId: 'existing',
          levelId: 1,
          selectedAnswers: [0, 0, 0],
          threshold: 0.66,
        );
        final before = await database.db.query(
          StorageSchemaV1.tableCourseProgress,
        );
        await expectLater(
          repository.resetCourseProgress('existing'),
          throwsA(isA<DatabaseException>()),
        );
        expect(
          await database.db.query(StorageSchemaV1.tableCourseProgress),
          before,
        );
        expect(
          await database.db.query(StorageSchemaV1.tableQuizAttempts),
          hasLength(1),
        );
        await database.db.execute('DROP TRIGGER fail_quiz_cleanup');
        await repository.resetCourseProgress('existing');
        expect(
          await database.db.query(StorageSchemaV1.tableCourseProgress),
          isEmpty,
        );
        expect(
          await database.db.query(StorageSchemaV1.tableQuizAttempts),
          isEmpty,
        );
      },
    );

    test(
      'Old achievements survive reopening without rewriting stored rows',
      () async {
        final before = await database.db.query(
          StorageSchemaV1.tableCourseProgress,
        );
        for (var read = 0; read < 2; read++) {
          final progress = await repository.getAllProgress('existing');
          expect(progress.length, 11);
          final knowledge = progress.singleWhere(
            (p) => p.levelId == CourseTopic.knowledge.storageId,
          );
          expect(knowledge.isCompleted, isTrue);
          expect(knowledge.attemptsCount, 2);
          expect(knowledge.contentVersion, '1.0.0');
          expect(knowledge.completedCheckpoints, [1, 2, 3, 4, 5]);
          expect(
            progress.singleWhere((p) => p.levelId == 10).isCompleted,
            isFalse,
          );
          expect(
            progress.singleWhere((p) => p.levelId == 11).isCompleted,
            isFalse,
          );
          expect(
            await repository.getLevelStatus('existing', 10),
            LevelStatus.available,
          );
          expect(
            await repository.getLevelStatus('existing', 11),
            LevelStatus.comingSoon,
          );
          expect(
            await repository.getLevelStatus('existing', 3),
            LevelStatus.completed,
          );
          expect(
            (await repository.getOverallProgress('existing')).completedLevelIds,
            {1, 2, 3, 4, 5},
          );
          await database.close();
          await database.open();
        }
        expect(
          await database.db.query(StorageSchemaV1.tableCourseProgress),
          before,
        );
        expect(
          (await repository.getAllProgress(
            'other',
          )).every((p) => !p.isCompleted),
          isTrue,
        );
      },
    );

    test(
      'All nine legacy topics retain achievements without completing new topics',
      () async {
        for (var id = 6; id <= 9; id++) {
          await database.db.insert(StorageSchemaV1.tableCourseProgress, {
            'owner_id': 'existing',
            'level_id': '$id',
            'content_version': '1.0.0',
            'current_step': 5,
            'completed_checkpoints_json': '[1,2,3,4,5]',
            'attempts_count': 2,
            'is_completed': 1,
            'updated_at_utc': '2026-10-18T12:00:00.000Z',
          });
        }
        final before = await database.db.query(
          StorageSchemaV1.tableCourseProgress,
        );
        await database.close();
        await database.open();
        final progress = await repository.getAllProgress('existing');
        expect(
          progress.where((p) => p.isCompleted).map((p) => p.levelId).toSet(),
          {1, 2, 3, 4, 5, 6, 7, 8, 9},
        );
        expect(
          progress
              .where((p) => p.levelId == 10 || p.levelId == 11)
              .every((p) => !p.isCompleted),
          isTrue,
        );
        expect(
          await database.db.query(StorageSchemaV1.tableCourseProgress),
          before,
        );
      },
    );

    test(
      'Skills sits between Instructions and Knowledge in the unlock order',
      () async {
        await database.db.update(
          StorageSchemaV1.tableCourseProgress,
          {
            'is_completed': 0,
            'current_step': 1,
            'completed_checkpoints_json': '[]',
          },
          where: 'owner_id = ? AND level_id = ?',
          whereArgs: ['existing', '3'],
        );
        // One curriculum order applies to every account, including test data.
        await repository.saveCheckpoint(
          ownerId: 'existing',
          levelId: 2,
          step: 5,
        );
        expect(
          await repository.getLevelStatus('existing', 3),
          LevelStatus.locked,
        );
        expect(
          await repository.getLevelStatus('existing', 10),
          LevelStatus.available,
        );
        await repository.completeLevel(ownerId: 'existing', levelId: 10);
        expect(
          await repository.getLevelStatus('existing', 3),
          LevelStatus.available,
        );
      },
    );

    test(
      'Unavailable topics cannot be completed and reset remains owner scoped',
      () async {
        await expectLater(
          repository.completeLevel(ownerId: 'existing', levelId: 11),
          throwsStateError,
        );
        await repository.resetCourseProgress('other');
        expect(
          (await repository.getOverallProgress(
            'existing',
          )).completedLevelsCount,
          5,
        );
        await repository.resetCourseProgress('existing');
        expect(
          (await repository.getAllProgress(
            'existing',
          )).every((p) => !p.isCompleted),
          isTrue,
        );
        expect(
          await repository.getLevelStatus('existing', 1),
          LevelStatus.available,
        );
      },
    );
  });
}
