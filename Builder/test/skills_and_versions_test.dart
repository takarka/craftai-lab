import 'dart:convert';
import 'dart:io';

import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/assistant/domain/assistant_config.dart';
import 'package:builder/features/assistant/infrastructure/persistent_assistant_repository.dart';
import 'package:builder/features/skills/domain/skill_preparation.dart';
import 'package:builder/features/skills/domain/skill_scenario.dart';
import 'package:builder/features/skills/domain/skill_templates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

SkillScenario assessment({String name = 'Проверочная', int revision = 1}) =>
    SkillScenario.fromJson({
      ...SkillTemplates.forLocale().first.toJson(),
      'name': name,
      'revision': revision,
    });

void main() {
  test(
    'Four bilingual templates round trip without granting assistant modules',
    () {
      for (final kk in [false, true]) {
        final templates = SkillTemplates.forLocale(isKk: kk);
        expect(templates.length, 4);
        expect(templates.map((s) => s.id).toSet().length, 4);
        for (final skill in templates) {
          skill.validate();
          final restored = SkillScenario.fromJson(
            jsonDecode(jsonEncode(skill.toJson())),
          );
          expect(restored.toJson(), skill.toJson());
          expect(() => skill.steps.add('mutate'), throwsUnsupportedError);
          expect(skill.toJson().containsKey('enabled_skills'), isFalse);
        }
      }
      final legacy = AssistantSnapshot.fromJson({'name': 'Прежний ассистент'});
      expect(legacy.skillScenarios, isEmpty);
    },
  );

  test('Missing input finishes preparation without sending or waiting', () {
    final skill = assessment();
    final incomplete = SkillPreparation.prepare(skill, {
      'Тема': 'Дроби',
      'Класс': '  ',
    });
    expect(incomplete.isReady, isFalse);
    expect(incomplete.missingInputs, ['Класс']);
    expect(incomplete.userPrompt, isNull);
    for (final topic in ['Дроби', 'Энергия']) {
      final ready = SkillPreparation.prepare(skill, {
        'Тема': topic,
        'Класс': '6',
        'extra': 'unused',
      });
      expect(ready.isReady, isTrue);
      final wire = jsonDecode(ready.userPrompt!) as Map<String, dynamic>;
      expect(wire['inputs'], {'Тема': topic, 'Класс': '6'});
      expect(wire['skill']['revision'], 1);
      expect(wire.containsKey('tools'), isFalse);
      expect(wire.containsKey('system'), isFalse);
    }
  });

  test('Invalid scenarios cannot be prepared', () {
    final invalid = SkillScenario.fromJson({
      ...assessment().toJson(),
      'steps': ['  '],
    });
    expect(invalid.validate, throwsArgumentError);
    expect(() => SkillPreparation.prepare(invalid, {}), throwsArgumentError);
  });

  group('Owner-scoped skill persistence and assistant snapshots', () {
    late Directory temp;
    late StorageDatabase db;
    late WorkspaceStorageService workspace;
    late PersistentAssistantRepository repository;

    setUp(() async {
      sqfliteFfiInit();
      temp = await Directory.systemTemp.createTemp('skills_versions_');
      db = StorageDatabase(
        databasePath: '${temp.path}/skills.db',
        databaseFactory: databaseFactoryFfi,
      );
      await db.open();
      workspace = WorkspaceStorageService(
        database: db,
        keyStorage: InMemorySecureKeyStorage(),
        installationId: 'skills-test',
      );
      for (final owner in ['alice', 'bob']) {
        await workspace.openWorkspace(ownerId: owner);
        await db.db.insert(StorageSchemaV1.tableAssistantConfigurations, {
          'owner_id': owner,
          'name': 'Ассистент $owner',
          'selected_category': 'standard',
          'enabled_skills_json': '["instructions"]',
          'system_rules_json': '["Краткие ответы"]',
          'state_revision': 1,
          'updated_at_utc': '2026-10-19T00:00:00.000Z',
        });
      }
      repository = PersistentAssistantRepository(
        database: db,
        workspaceService: workspace,
      );
    });

    tearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });

    test(
      'Create/edit/reopen preserves fields and all other assistant settings',
      () async {
        await repository.saveSkill('alice', assessment());
        var versions = await repository.getVersions('alice');
        expect(versions.length, 2); // Includes a restorable pre-edit baseline.
        expect(versions.last.snapshot.skillScenarios, isEmpty);
        expect(
          versions.first.snapshot.skillScenarios.single.name,
          'Проверочная',
        );
        await repository.saveSkill(
          'alice',
          assessment(name: 'Улучшенная проверочная'),
        );
        await db.close();
        await db.open();
        final saved = (await repository.getSkills('alice')).single;
        expect(saved.revision, 2);
        expect(saved.name, 'Улучшенная проверочная');
        expect(saved.requiredInputs, ['Тема', 'Класс']);
        final config = (await repository.getConfiguration('alice'))!;
        expect(config.name, 'Ассистент alice');
        expect(config.enabledSkills, {'instructions'});
        expect(config.systemRules, ['Краткие ответы']);
        await expectLater(
          repository.saveSkill('alice', assessment()),
          throwsStateError,
        );
        expect((await repository.getSkills('alice')).single.revision, 2);
      },
    );

    test(
      'Two concurrent edits of different skills do not lose either scenario',
      () async {
        await Future.wait([
          repository.saveSkill('alice', assessment()),
          repository.saveSkill('alice', SkillTemplates.forLocale()[1]),
        ]);
        expect((await repository.getSkills('alice')).length, 2);
        expect(
          (await repository.getVersions(
            'alice',
          )).first.snapshot.skillScenarios.length,
          2,
        );
      },
    );

    test(
      'Same skill ID in another account is isolated from update and delete',
      () async {
        await repository.saveSkill('alice', assessment());
        await repository.saveSkill('bob', assessment(name: 'Навык Боба'));
        await repository.deleteSkill('alice', 'assessment');
        expect(await repository.getSkills('alice'), isEmpty);
        expect((await repository.getSkills('bob')).single.name, 'Навык Боба');
        final count = (await repository.getVersions('alice')).length;
        await repository.deleteSkill('alice', 'assessment');
        expect((await repository.getVersions('alice')).length, count);
      },
    );

    test(
      'Rollback restores scenarios and a legacy snapshot clears them without granting tools',
      () async {
        await repository.saveSkill('alice', assessment());
        await repository.saveSkill('alice', assessment(name: 'Изменено'));
        await repository.deleteSkill('alice', 'assessment');
        await repository.rollbackToVersion(
          ownerId: 'alice',
          targetVersionNumber: 2,
          allowedSkills: {},
        );
        expect(
          (await repository.getSkills('alice')).single.name,
          'Проверочная',
        );
        expect(
          (await repository.getConfiguration('alice'))!.enabledSkills,
          isEmpty,
        );
        // Simulate an actual pre-Skills snapshot with the optional field absent.
        final row = (await db.db.query(
          StorageSchemaV1.tableAssistantVersions,
          where: 'owner_id = ? AND version_number = ?',
          whereArgs: ['alice', 1],
        )).single;
        final json =
            jsonDecode(row['snapshot_json'] as String) as Map<String, dynamic>;
        json.remove('skill_scenarios');
        await db.db.update(
          StorageSchemaV1.tableAssistantVersions,
          {'snapshot_json': jsonEncode(json)},
          where: 'owner_id = ? AND version_number = ?',
          whereArgs: ['alice', 1],
        );
        await repository.rollbackToVersion(
          ownerId: 'alice',
          targetVersionNumber: 1,
          allowedSkills: {},
        );
        expect(await repository.getSkills('alice'), isEmpty);
      },
    );

    test(
      'Version write failure rolls back skill mutation and configuration together',
      () async {
        await repository.saveSkill('alice', assessment());
        final config = (await repository.getConfiguration('alice'))!;
        await db.db.execute(
          '''CREATE TEMP TRIGGER reject_version BEFORE INSERT ON assistant_versions
        BEGIN SELECT RAISE(ABORT, 'test version failure'); END;''',
        );
        await expectLater(
          repository.saveSkill('alice', assessment(name: 'Не сохранять')),
          throwsA(isA<DatabaseException>()),
        );
        expect(
          (await repository.getSkills('alice')).single.name,
          'Проверочная',
        );
        expect(
          (await repository.getConfiguration('alice'))!.stateRevision,
          config.stateRevision,
        );
        expect((await repository.getVersions('alice')).length, 2);
      },
    );

    test(
      'Reset and account purge remove scenarios only for the chosen owner',
      () async {
        await repository.saveSkill('alice', assessment());
        await repository.saveSkill('bob', assessment());
        await workspace.openWorkspace(ownerId: 'alice');
        await repository.resetAssistantWorkspace('alice');
        expect(await repository.getSkills('alice'), isEmpty);
        expect((await repository.getSkills('bob')).length, 1);
        await workspace.purgeOwnerData(ownerId: 'bob');
        expect(await repository.getSkills('bob'), isEmpty);
      },
    );

    test(
      'Opening an existing v1 database adds Skills without rewriting its config',
      () async {
        final before = await db.db.query(
          StorageSchemaV1.tableAssistantConfigurations,
        );
        await db.db.execute('DROP TABLE skill_scenarios');
        await db.close();
        await db.open();
        await db.close();
        await db.open();
        expect(await repository.getSkills('alice'), isEmpty);
        expect(
          await db.db.query(StorageSchemaV1.tableAssistantConfigurations),
          before,
        );
        await repository.saveSkill('alice', assessment());
        expect((await repository.getSkills('alice')).length, 1);
      },
    );
  });
}
