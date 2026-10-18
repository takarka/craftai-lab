import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../domain/instruction_models.dart';
import '../domain/instructions_repository.dart';

class PersistentInstructionsRepository implements InstructionsRepository {
  final StorageDatabase database;

  PersistentInstructionsRepository({required this.database});

  Future<void> _ensureOpen() async {
    if (!database.isOpen) {
      await database.open();
    }
  }

  @override
  Future<InstructionConfig> getInstructionConfig(String ownerId) async {
    await _ensureOpen();

    // 1. Read assistant configuration row to get system_rules_json
    final configRows = await database.db.query(
      StorageSchemaV1.tableAssistantConfigurations,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      limit: 1,
    );

    List<String> systemRules = [];
    if (configRows.isNotEmpty) {
      final raw = configRows.first['system_rules_json'] as String?;
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as List<dynamic>;
          systemRules = decoded.map((e) => e.toString()).toList();
        } catch (_) {}
      }
    }

    // 2. Read instruction_rules table
    final ruleRows = await database.db.query(
      StorageSchemaV1.tableInstructionRules,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'sort_order ASC',
    );

    if (ruleRows.isEmpty) {
      // First time initialization: seed default presets into tableInstructionRules
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      final batch = database.db.batch();
      final defaultRules = InstructionPresets.defaultRules;

      for (final rule in defaultRules) {
        batch.insert(StorageSchemaV1.tableInstructionRules, {
          'id': '${rule.id}_$ownerId',
          'owner_id': ownerId,
          'group_name': rule.group.id,
          'rule_text': rule.text,
          'is_enabled': rule.isEnabled ? 1 : 0,
          'sort_order': rule.sortOrder,
          'source': 'preset',
          'revision': 1,
          'updated_at_utc': nowUtc,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);

      // Parse from systemRules or return default config
      return InstructionConfig.fromSystemRules(systemRules, ownerId: ownerId);
    }

    // Parse persisted rules from DB
    final dbRules = <InstructionRule>[];
    for (final row in ruleRows) {
      final id = row['id'] as String;
      final group = InstructionGroup.fromId(row['group_name'] as String);
      final text = row['rule_text'] as String;
      final isEnabled = (row['is_enabled'] as int) == 1;
      final sortOrder = row['sort_order'] as int;
      final source = row['source'] as String;
      final isCustom = source == 'custom';
      final revision = row['revision'] as int;

      // Match preset explanation & title if available
      String title = row['group_name'] as String;
      String explanation = '';
      for (final preset in InstructionPresets.defaultRules) {
        if (id.startsWith(preset.id)) {
          title = preset.title;
          explanation = preset.explanation;
          break;
        }
      }

      if (isCustom) {
        title = 'Своё правило';
        explanation = 'Пользовательское правило';
      }

      dbRules.add(
        InstructionRule(
          id: id,
          ownerId: ownerId,
          group: group,
          title: title,
          text: text,
          explanation: explanation,
          isEnabled: isEnabled,
          sortOrder: sortOrder,
          isCustom: isCustom,
          revision: revision,
        ),
      );
    }

    // Check if raw mode was saved in systemRules
    final isRaw = systemRules.isNotEmpty && systemRules.first == '__RAW_MODE__';
    final rawText = (isRaw && systemRules.length > 1)
        ? systemRules[1]
        : InstructionConfig.assemble(dbRules);

    return InstructionConfig(
      isRawMode: isRaw,
      rawText: rawText,
      rules: dbRules,
    );
  }

  @override
  Future<void> saveInstructionConfig(
    String ownerId,
    InstructionConfig config,
  ) async {
    await _ensureOpen();
    final nowUtc = DateTime.now().toUtc().toIso8601String();

    await database.db.transaction((txn) async {
      // 1. Sync rules in tableInstructionRules
      for (final rule in config.rules) {
        final ruleId = rule.id.contains(ownerId)
            ? rule.id
            : '${rule.id}_$ownerId';
        await txn.insert(StorageSchemaV1.tableInstructionRules, {
          'id': ruleId,
          'owner_id': ownerId,
          'group_name': rule.group.id,
          'rule_text': rule.text,
          'is_enabled': rule.isEnabled ? 1 : 0,
          'sort_order': rule.sortOrder,
          'source': rule.isCustom ? 'custom' : 'preset',
          'revision': rule.revision + 1,
          'updated_at_utc': nowUtc,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // 2. Sync system_rules_json in tableAssistantConfigurations
      final systemRules = config.toSystemRules();
      await txn.update(
        StorageSchemaV1.tableAssistantConfigurations,
        {
          'system_rules_json': jsonEncode(systemRules),
          'updated_at_utc': nowUtc,
        },
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
    });
  }

  @override
  Future<void> addCustomRule(String ownerId, InstructionRule rule) async {
    await _ensureOpen();
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final ruleId = rule.id.contains(ownerId) ? rule.id : '${rule.id}_$ownerId';

    await database.db.insert(StorageSchemaV1.tableInstructionRules, {
      'id': ruleId,
      'owner_id': ownerId,
      'group_name': rule.group.id,
      'rule_text': rule.text,
      'is_enabled': rule.isEnabled ? 1 : 0,
      'sort_order': rule.sortOrder,
      'source': 'custom',
      'revision': 1,
      'updated_at_utc': nowUtc,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteCustomRule(String ownerId, String ruleId) async {
    await _ensureOpen();
    await database.db.delete(
      StorageSchemaV1.tableInstructionRules,
      where: 'id = ? AND owner_id = ?',
      whereArgs: [ruleId, ownerId],
    );
  }

  @override
  Future<void> resetToDefaults(String ownerId) async {
    await _ensureOpen();
    final nowUtc = DateTime.now().toUtc().toIso8601String();

    await database.db.transaction((txn) async {
      await txn.delete(
        StorageSchemaV1.tableInstructionRules,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );

      final defaultRules = InstructionPresets.defaultRules;
      for (final rule in defaultRules) {
        await txn.insert(StorageSchemaV1.tableInstructionRules, {
          'id': '${rule.id}_$ownerId',
          'owner_id': ownerId,
          'group_name': rule.group.id,
          'rule_text': rule.text,
          'is_enabled': 0,
          'sort_order': rule.sortOrder,
          'source': 'preset',
          'revision': 1,
          'updated_at_utc': nowUtc,
        });
      }

      await txn.update(
        StorageSchemaV1.tableAssistantConfigurations,
        {'system_rules_json': '[]', 'updated_at_utc': nowUtc},
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
    });
  }
}

final class InMemoryInstructionsRepository implements InstructionsRepository {
  final Map<String, InstructionConfig> _configs = {};

  @override
  Future<InstructionConfig> getInstructionConfig(String ownerId) async {
    return _configs[ownerId] ??
        InstructionConfig(rules: InstructionPresets.defaultRules);
  }

  @override
  Future<void> saveInstructionConfig(
    String ownerId,
    InstructionConfig config,
  ) async {
    _configs[ownerId] = config;
  }

  @override
  Future<void> addCustomRule(String ownerId, InstructionRule rule) async {
    final current = await getInstructionConfig(ownerId);
    final updatedRules = [...current.rules, rule];
    _configs[ownerId] = InstructionConfig(
      isRawMode: current.isRawMode,
      rawText: current.rawText,
      rules: updatedRules,
    );
  }

  @override
  Future<void> deleteCustomRule(String ownerId, String ruleId) async {
    final current = await getInstructionConfig(ownerId);
    final updatedRules = current.rules.where((r) => r.id != ruleId).toList();
    _configs[ownerId] = InstructionConfig(
      isRawMode: current.isRawMode,
      rawText: current.rawText,
      rules: updatedRules,
    );
  }

  @override
  Future<void> resetToDefaults(String ownerId) async {
    _configs[ownerId] = InstructionConfig(
      rules: InstructionPresets.defaultRules,
    );
  }
}
