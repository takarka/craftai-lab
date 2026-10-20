import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../../../core/storage/workspace/workspace_storage_service.dart';
import '../../models/domain/model_category.dart';
import '../../skills/domain/skill_scenario.dart';
import '../../skills/domain/skills_repository.dart';
import '../domain/assistant_config.dart';
import '../domain/assistant_repository.dart';

class PersistentAssistantRepository
    implements AssistantRepository, SkillsRepository {
  PersistentAssistantRepository({
    required this.database,
    required this.workspaceService,
  });

  final StorageDatabase database;
  final WorkspaceStorageService workspaceService;

  Future<void> _ensureOpen() async {
    if (!database.isOpen) {
      await database.open();
    }
  }

  Future<List<SkillScenario>> _readSkills(
    DatabaseExecutor executor,
    String ownerId,
  ) async {
    final rows = await executor.query(
      StorageSchemaV1.tableSkillScenarios,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'id ASC',
    );
    return rows
        .map(
          (row) => SkillScenario.fromJson(
            jsonDecode(row['scenario_json'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  @override
  Future<List<SkillScenario>> getSkills(String ownerId) async {
    await _ensureOpen();
    return _readSkills(database.db, ownerId);
  }

  @override
  Future<void> saveSkill(String ownerId, SkillScenario skill) async {
    skill.validate();
    await _ensureOpen();
    await database.transaction((txn) async {
      final existing = await _readSkills(txn, ownerId);
      final previous = existing.where((s) => s.id == skill.id).firstOrNull;
      if (previous != null && previous.revision != skill.revision) {
        throw StateError('Skill was changed; reload before saving');
      }
      await _ensureInitialSkillVersion(txn, ownerId);
      final updated = skill.withRevision((previous?.revision ?? 0) + 1);
      await txn.insert(StorageSchemaV1.tableSkillScenarios, {
        'owner_id': ownerId,
        'id': skill.id,
        'scenario_json': jsonEncode(updated.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _commitSkillEdit(txn, ownerId, 'Сохранение навыка: ${skill.name}');
    });
  }

  @override
  Future<void> deleteSkill(String ownerId, String skillId) async {
    await _ensureOpen();
    await database.transaction((txn) async {
      final existing = await _readSkills(txn, ownerId);
      if (!existing.any((skill) => skill.id == skillId)) return;
      await _ensureInitialSkillVersion(txn, ownerId);
      final count = await txn.delete(
        StorageSchemaV1.tableSkillScenarios,
        where: 'owner_id = ? AND id = ?',
        whereArgs: [ownerId, skillId],
      );
      if (count > 0) await _commitSkillEdit(txn, ownerId, 'Удаление навыка');
    });
  }

  Future<void> _ensureInitialSkillVersion(
    Transaction txn,
    String ownerId,
  ) async {
    final versions = await txn.query(
      StorageSchemaV1.tableAssistantVersions,
      columns: ['version_number'],
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      limit: 1,
    );
    if (versions.isEmpty) {
      await _commitSkillEdit(txn, ownerId, 'Создание ассистента');
    }
  }

  Future<void> _commitSkillEdit(
    Transaction txn,
    String ownerId,
    String reason,
  ) async {
    final rows = await txn.query(
      StorageSchemaV1.tableAssistantConfigurations,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    if (rows.isEmpty) throw StateError('Assistant configuration not found');
    final config = _parseConfig(rows.first);
    await _commitChange(
      txn,
      ownerId: ownerId,
      name: config.name,
      selectedCategory: config.selectedCategory,
      enabledSkills: config.enabledSkills,
      systemRules: config.systemRules,
      reason: reason,
    );
  }

  @override
  Future<AssistantConfig?> getConfiguration(String ownerId) async {
    await _ensureOpen();
    final rows = await database.db.query(
      StorageSchemaV1.tableAssistantConfigurations,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );

    if (rows.isEmpty) return null;
    final row = rows.first;
    return _parseConfig(row);
  }

  AssistantConfig _parseConfig(Map<String, dynamic> row) {
    final catName = row['selected_category'] as String?;
    final cat = catName != null ? ModelCategory.fromString(catName) : null;
    final skillsRaw =
        jsonDecode(row['enabled_skills_json'] as String) as List<dynamic>;
    final rulesRaw =
        jsonDecode(row['system_rules_json'] as String) as List<dynamic>;

    return AssistantConfig(
      ownerId: row['owner_id'] as String,
      name: row['name'] as String,
      selectedCategory: cat,
      enabledSkills: skillsRaw.map((e) => e.toString()).toSet(),
      systemRules: rulesRaw.map((e) => e.toString()).toList(),
      stateRevision: row['state_revision'] as int,
      updatedAtUtc: DateTime.parse(row['updated_at_utc'] as String),
    );
  }

  @override
  Future<List<AssistantVersion>> getVersions(String ownerId) async {
    await _ensureOpen();

    // Query active document IDs to detect missing resources (ADR-02)
    final docRows = await database.db.query(
      StorageSchemaV1.tableKnowledgeDocuments,
      columns: ['id'],
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    final activeDocIds = docRows.map((r) => r['id'] as String).toSet();

    var rows = await database.db.query(
      StorageSchemaV1.tableAssistantVersions,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'version_number DESC',
    );

    // If no versions exist yet, seed initial v1 from current config (F09-06)
    if (rows.isEmpty) {
      final config = await getConfiguration(ownerId);
      if (config != null) {
        await commitChange(
          ownerId: ownerId,
          name: config.name,
          selectedCategory: config.selectedCategory,
          enabledSkills: config.enabledSkills,
          systemRules: config.systemRules,
          reason: 'Создание ассистента',
        );
        rows = await database.db.query(
          StorageSchemaV1.tableAssistantVersions,
          where: 'owner_id = ?',
          whereArgs: [ownerId],
          orderBy: 'version_number DESC',
        );
      }
    }

    final latestVersionNumber = rows.isNotEmpty
        ? (rows.first['version_number'] as int)
        : 1;

    return rows.map((row) {
      final vNum = row['version_number'] as int;
      final snapshotJson =
          jsonDecode(row['snapshot_json'] as String) as Map<String, dynamic>;
      final snapshot = AssistantSnapshot.fromJson(snapshotJson);

      // Identify referenced documents that are permanently deleted
      final missingDocs = snapshot.documentIds
          .where((id) => !activeDocIds.contains(id))
          .toList();

      return AssistantVersion(
        versionNumber: vNum,
        createdAtUtc: DateTime.parse(row['created_at_utc'] as String),
        reason: row['reason'] as String,
        snapshot: snapshot,
        parentId: row['parent_id'] as String?,
        schemaVersion: row['schema_version'] as int,
        isCurrent: vNum == latestVersionNumber,
        missingResources: missingDocs,
      );
    }).toList();
  }

  @override
  Future<AssistantVersion> commitChange({
    required String ownerId,
    required String name,
    ModelCategory? selectedCategory,
    required Set<String> enabledSkills,
    List<String>? systemRules,
    required String reason,
  }) async {
    await _ensureOpen();

    return database.transaction(
      (txn) => _commitChange(
        txn,
        ownerId: ownerId,
        name: name,
        selectedCategory: selectedCategory,
        enabledSkills: enabledSkills,
        systemRules: systemRules,
        reason: reason,
      ),
    );
  }

  Future<AssistantVersion> _commitChange(
    DatabaseExecutor txn, {
    required String ownerId,
    required String name,
    ModelCategory? selectedCategory,
    required Set<String> enabledSkills,
    List<String>? systemRules,
    required String reason,
  }) async {
    // 1. Fetch current revision
    final configRows = await txn.query(
      StorageSchemaV1.tableAssistantConfigurations,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );

    final nextRevision = configRows.isNotEmpty
        ? (configRows.first['state_revision'] as int) + 1
        : 1;

    // 2. Fetch max version number
    final maxVRow = await txn.rawQuery(
      'SELECT MAX(version_number) as max_v FROM ${StorageSchemaV1.tableAssistantVersions} WHERE owner_id = ?',
      [ownerId],
    );
    final currentMaxV = (maxVRow.first['max_v'] as int?) ?? 0;
    final nextVersion = currentMaxV + 1;

    // 3. Count facts and documents
    final factsCountRow = await txn.rawQuery(
      'SELECT COUNT(*) as count FROM ${StorageSchemaV1.tableMemoryFacts} WHERE owner_id = ?',
      [ownerId],
    );
    final factsCount = (factsCountRow.first['count'] as int?) ?? 0;

    final docsRows = await txn.query(
      StorageSchemaV1.tableKnowledgeDocuments,
      columns: ['id'],
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    final docIds = docsRows.map((r) => r['id'] as String).toList();

    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final rules =
        systemRules ??
        (configRows.isNotEmpty
            ? (jsonDecode(configRows.first['system_rules_json'] as String)
                      as List<dynamic>)
                  .map((e) => e.toString())
                  .toList()
            : <String>[]);

    final snapshot = AssistantSnapshot(
      name: name,
      selectedCategory: selectedCategory,
      enabledSkills: enabledSkills,
      systemRules: rules,
      memoryFactsCount: factsCount,
      documentsCount: docIds.length,
      documentIds: docIds,
      skillScenarios: await _readSkills(txn, ownerId),
    );

    // 4. Update configuration row
    await txn.insert(StorageSchemaV1.tableAssistantConfigurations, {
      'owner_id': ownerId,
      'name': name,
      'selected_category': selectedCategory?.name,
      'enabled_skills_json': jsonEncode(enabledSkills.toList()..sort()),
      'system_rules_json': jsonEncode(rules),
      'state_revision': nextRevision,
      'updated_at_utc': nowUtc,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // 5. Insert new version record
    await txn.insert(StorageSchemaV1.tableAssistantVersions, {
      'owner_id': ownerId,
      'version_number': nextVersion,
      'created_at_utc': nowUtc,
      'reason': reason,
      'parent_id': currentMaxV > 0 ? currentMaxV.toString() : null,
      'schema_version': 1,
      'snapshot_json': jsonEncode(snapshot.toJson()),
    });

    return AssistantVersion(
      versionNumber: nextVersion,
      createdAtUtc: DateTime.parse(nowUtc),
      reason: reason,
      snapshot: snapshot,
      parentId: currentMaxV > 0 ? currentMaxV.toString() : null,
      schemaVersion: 1,
      isCurrent: true,
    );
  }

  @override
  Future<void> rollbackToVersion({
    required String ownerId,
    required int targetVersionNumber,
    required Set<String> allowedSkills,
  }) async {
    await _ensureOpen();

    await database.transaction((txn) async {
      final versionRows = await txn.query(
        StorageSchemaV1.tableAssistantVersions,
        where: 'owner_id = ? AND version_number = ?',
        whereArgs: [ownerId, targetVersionNumber],
      );

      if (versionRows.isEmpty) {
        throw ArgumentError('Версия $targetVersionNumber не найдена');
      }

      final snapshotJson =
          jsonDecode(versionRows.first['snapshot_json'] as String)
              as Map<String, dynamic>;
      final snapshot = AssistantSnapshot.fromJson(snapshotJson);

      // Filter skills by course progress permissions (F09-08 and ADR-01)
      final safeSkills = snapshot.enabledSkills
          .where((s) => allowedSkills.contains(s))
          .toSet();

      // Restore declarative scenarios only. No run, schedule or permission is created.
      await txn.delete(
        StorageSchemaV1.tableSkillScenarios,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      for (final skill in snapshot.skillScenarios) {
        skill.validate();
        await txn.insert(StorageSchemaV1.tableSkillScenarios, {
          'owner_id': ownerId,
          'id': skill.id,
          'scenario_json': jsonEncode(skill.toJson()),
        });
      }
      await _commitChange(
        txn,
        ownerId: ownerId,
        name: snapshot.name,
        selectedCategory: snapshot.selectedCategory,
        enabledSkills: safeSkills,
        systemRules: snapshot.systemRules,
        reason: 'Восстановление версии $targetVersionNumber',
      );
    });
  }

  @override
  Future<LocalDataSummary> getLocalDataSummary(String ownerId) async {
    await _ensureOpen();

    final convs = await database.db.rawQuery(
      'SELECT COUNT(*) as count FROM ${StorageSchemaV1.tableConversations} WHERE owner_id = ?',
      [ownerId],
    );
    final msgs = await database.db.rawQuery(
      'SELECT COUNT(*) as count FROM ${StorageSchemaV1.tableMessages} WHERE owner_id = ?',
      [ownerId],
    );
    final facts = await database.db.rawQuery(
      'SELECT COUNT(*) as count FROM ${StorageSchemaV1.tableMemoryFacts} WHERE owner_id = ?',
      [ownerId],
    );
    final docs = await database.db.rawQuery(
      'SELECT COUNT(*) as count FROM ${StorageSchemaV1.tableKnowledgeDocuments} WHERE owner_id = ?',
      [ownerId],
    );
    final chunks = await database.db.rawQuery(
      'SELECT COUNT(*) as count FROM ${StorageSchemaV1.tableKnowledgeChunks} WHERE owner_id = ?',
      [ownerId],
    );
    final traces = await database.db.rawQuery(
      'SELECT COUNT(*) as count FROM ${StorageSchemaV1.tableRequestTraces} WHERE owner_id = ?',
      [ownerId],
    );
    final versions = await database.db.rawQuery(
      'SELECT COUNT(*) as count FROM ${StorageSchemaV1.tableAssistantVersions} WHERE owner_id = ?',
      [ownerId],
    );

    return LocalDataSummary(
      conversationsCount: (convs.first['count'] as int?) ?? 0,
      messagesCount: (msgs.first['count'] as int?) ?? 0,
      memoryFactsCount: (facts.first['count'] as int?) ?? 0,
      documentsCount: (docs.first['count'] as int?) ?? 0,
      chunksCount: (chunks.first['count'] as int?) ?? 0,
      tracesCount: (traces.first['count'] as int?) ?? 0,
      versionsCount: (versions.first['count'] as int?) ?? 0,
    );
  }

  @override
  Future<int?> getStorageRetentionDays(String ownerId) async {
    await _ensureOpen();
    final rows = await database.db.query(
      StorageSchemaV1.tableTeacherPreferences,
      columns: ['storage_retention_days'],
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    if (rows.isEmpty) return null;
    return rows.first['storage_retention_days'] as int?;
  }

  @override
  Future<void> setStorageRetentionDays(String ownerId, int? days) async {
    await _ensureOpen();
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    await database.db.update(
      StorageSchemaV1.tableTeacherPreferences,
      {'storage_retention_days': days, 'updated_at_utc': nowUtc},
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
  }

  @override
  Future<void> resetAssistantWorkspace(String ownerId) async {
    await _ensureOpen();

    // 1. Advance workspace epoch fence (F09-10)
    await workspaceService.bumpWorkspaceEpoch(ownerId: ownerId);

    // 2. Perform atomic deletion in transaction
    await database.transaction((txn) async {
      await txn.delete(
        StorageSchemaV1.tableSkillScenarios,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableAssistantVersions,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableConversations,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableMessages,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableRequestTraces,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableKnowledgeDocuments,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableDocumentRevisions,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableKnowledgeChunks,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableMemoryFacts,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableToolGrants,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tablePendingActions,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableToolInvocations,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableCourseProgress,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableQuizAttempts,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tableFileStagingJournal,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );

      // Reset assistant_configurations to initial baseline
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        StorageSchemaV1.tableAssistantConfigurations,
        {
          'name': '',
          'selected_category': null,
          'enabled_skills_json': '[]',
          'system_rules_json': '[]',
          'state_revision': 1,
          'updated_at_utc': nowUtc,
        },
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
    });
  }
}
