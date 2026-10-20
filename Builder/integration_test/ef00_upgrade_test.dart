import 'dart:io';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/assistant/infrastructure/persistent_assistant_repository.dart';
import 'package:builder/features/course/domain/course_catalog.dart';
import 'package:builder/features/course/infrastructure/persistent_course_repository.dart';
import 'package:builder/features/course/presentation/course_character.dart';
import 'package:builder/features/skills/domain/skill_templates.dart';
import 'package:builder/ui_kit/identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'EF-00 native SQLite upgrade, Skills, character and owner-scoped reset',
    (tester) async {
      final root = await getTemporaryDirectory();
      debugPrint('EF00: temporary directory ready');
      final temp = await Directory(root.path).createTemp('ef00_upgrade_');
      final database = StorageDatabase(databasePath: '${temp.path}/upgrade.db');
      addTearDown(() async {
        await database.close();
        await temp.delete(recursive: true);
      });
      final workspace = WorkspaceStorageService(
        database: database,
        keyStorage: InMemorySecureKeyStorage(),
        installationId: 'ef00-native',
      );
      await workspace.openWorkspace(ownerId: 'ef00-test');
      debugPrint('EF00: first workspace ready');
      await workspace.openWorkspace(ownerId: 'ef00-other');
      for (final owner in ['ef00-test', 'ef00-other']) {
        await database.db.insert(StorageSchemaV1.tableAssistantConfigurations, {
          'owner_id': owner,
          'name': 'EF00 test',
          'selected_category': 'standard',
          'enabled_skills_json': '[]',
          'system_rules_json': '[]',
          'state_revision': 1,
          'updated_at_utc': '2026-10-19T00:00:00.000Z',
        });
      }
      final assistant = PersistentAssistantRepository(
        database: database,
        workspaceService: workspace,
      );
      final course = PersistentCourseRepository(database: database);
      // Model a stored nine-topic installation, without altering the real workspace.
      for (var id = 1; id <= 9; id++) {
        await database.db.insert(StorageSchemaV1.tableCourseProgress, {
          'owner_id': 'ef00-test',
          'level_id': '$id',
          'content_version': '1.0.0',
          'current_step': 5,
          'completed_checkpoints_json': '[1,2,3,4,5]',
          'attempts_count': 2,
          'is_completed': 1,
          'updated_at_utc': '2026-10-18T12:00:00.000Z',
        });
      }
      await database.db.execute('DROP TABLE skill_scenarios');
      final before = await database.db.query(
        StorageSchemaV1.tableCourseProgress,
      );
      await database.close();
      await database.open();
      await database.close();
      await database.open();
      debugPrint('EF00: legacy database reopened twice');
      expect(
        await database.db.query(StorageSchemaV1.tableCourseProgress),
        before,
      );
      final progress = await course.getAllProgress('ef00-test');
      expect(progress, hasLength(11));
      expect(progress.where((p) => p.isCompleted), hasLength(9));
      expect(
        progress.where((p) => p.levelId >= 10).every((p) => !p.isCompleted),
        isTrue,
      );
      for (final locale in ['ru', 'kk']) {
        expect(
          CourseCatalog.getLevels(locale: locale).map((l) => l.displayOrder),
          List.generate(11, (i) => i + 1),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Center(
                child: CourseCharacter(completedLevels: {1, 2, 10}, size: 200),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<BuilderCharacter>(find.byType(BuilderCharacter))
              .unlockedModules,
          {1, 2, 10},
        );
        expect(tester.takeException(), isNull);
      }
      await assistant.saveSkill('ef00-test', SkillTemplates.forLocale().first);
      debugPrint('EF00: character and first skill verified');
      await assistant.saveSkill('ef00-other', SkillTemplates.forLocale().first);
      expect(await assistant.getVersions('ef00-test'), isNotEmpty);
      await course.completeLevel(ownerId: 'ef00-test', levelId: 10);
      await workspace.openWorkspace(ownerId: 'ef00-test');
      await assistant.resetAssistantWorkspace('ef00-test');
      expect(await assistant.getSkills('ef00-test'), isEmpty);
      expect(
        (await course.getAllProgress('ef00-test')).every((p) => !p.isCompleted),
        isTrue,
      );
      expect(await assistant.getSkills('ef00-other'), hasLength(1));
      await workspace.purgeOwnerData(ownerId: 'ef00-other');
      expect(await assistant.getSkills('ef00-other'), isEmpty);
      debugPrint('EF00: reset and owner deletion verified');
    },
  );
}
