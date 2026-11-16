import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v2.dart';
import '../../../core/storage/security/secure_key_storage.dart';
import '../../../core/storage/security/storage_cipher.dart';
import '../domain/lab_agent.dart';

abstract interface class AgentsCache {
  Future<List<LabAgent>?> read();
  Future<void> replace(List<LabAgent> agents);
  Future<String?> selected();
  Future<void> select(String? id);
  Future<void> clearAgentData(String id);
  Future<Map<String, dynamic>?> readDraft(String id, int epoch);
  Future<void> saveDraft(String id, int epoch, Map<String, dynamic>? draft);
}

class MemoryAgentsCache implements AgentsCache {
  List<LabAgent>? _agents;
  String? _selected;
  final _drafts = <String, Map<String, dynamic>>{};
  @override
  Future<List<LabAgent>?> read() async => _agents;
  @override
  Future<void> replace(List<LabAgent> agents) async =>
      _agents = List.unmodifiable(agents);
  @override
  Future<String?> selected() async => _selected;
  @override
  Future<void> select(String? id) async => _selected = id;
  @override
  Future<void> clearAgentData(String id) async =>
      _drafts.removeWhere((key, _) => key.startsWith('$id:'));
  @override
  Future<Map<String, dynamic>?> readDraft(String id, int epoch) async =>
      _drafts['$id:$epoch'];
  @override
  Future<void> saveDraft(
    String id,
    int epoch,
    Map<String, dynamic>? draft,
  ) async {
    if (draft == null) {
      _drafts.remove('$id:$epoch');
    } else {
      _drafts['$id:$epoch'] = Map.of(draft);
    }
  }
}

class SqliteAgentsCache implements AgentsCache {
  SqliteAgentsCache({
    required this.database,
    required this.ownerId,
    required this.keys,
    required this.installationId,
  });
  final StorageDatabase database;
  final String ownerId;
  final SecureKeyStorage keys;
  final String installationId;

  Future<StorageCipher> _cipher() async {
    if (!database.isOpen) await database.open();
    return StorageCipher(
      key: await keys.getOrCreateStorageKey(installationId: installationId),
    );
  }

  @override
  Future<List<LabAgent>?> read() async {
    final cipher = await _cipher();
    final rows = await database.db.query(
      'lab_agents_cache',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    if (rows.isEmpty) return null;
    return rows
        .map(
          (row) => LabAgent(
            jsonDecode(cipher.decrypt(row['snapshot'] as String))
                as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  @override
  Future<void> replace(List<LabAgent> agents) async {
    final cipher = await _cipher();
    await database.transaction((txn) async {
      final old = await txn.query(
        'lab_agents_cache',
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      final byId = {for (final agent in agents) agent.id: agent};
      for (final row in old) {
        final id = row['agent_id'] as String;
        final previous = LabAgent(
          jsonDecode(cipher.decrypt(row['snapshot'] as String))
              as Map<String, dynamic>,
        );
        if (!byId.containsKey(id) || byId[id]!.epoch != previous.epoch) {
          await _clear(txn, id);
        }
      }
      await txn.delete(
        'lab_agents_cache',
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      for (final agent in agents) {
        await txn.insert('lab_agents_cache', {
          'owner_id': ownerId,
          'agent_id': agent.id,
          'snapshot': cipher.encrypt(jsonEncode(agent.json)),
        });
      }
    });
  }

  @override
  Future<String?> selected() async {
    await _cipher();
    final rows = await database.db.query(
      'lab_agent_selection',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    return rows.firstOrNull?['agent_id'] as String?;
  }

  @override
  Future<void> select(String? id) async {
    await _cipher();
    if (id == null) {
      await database.db.delete(
        'lab_agent_selection',
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
    } else {
      await database.db.insert('lab_agent_selection', {
        'owner_id': ownerId,
        'agent_id': id,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _clear(DatabaseExecutor db, String id) async {
    // Child rows first to respect legacy foreign keys. Course progress is independent.
    for (final table in [
      ...StorageSchemaV2.agentTables.reversed,
      'lab_agent_drafts',
    ]) {
      await db.delete(
        table,
        where: 'owner_id = ? AND agent_id = ?',
        whereArgs: [ownerId, id],
      );
    }
  }

  @override
  Future<void> clearAgentData(String id) async {
    await _cipher();
    await database.transaction((txn) => _clear(txn, id));
  }

  @override
  Future<Map<String, dynamic>?> readDraft(String id, int epoch) async {
    final cipher = await _cipher();
    final rows = await database.db.query(
      'lab_agent_drafts',
      where: 'owner_id = ? AND agent_id = ? AND epoch = ?',
      whereArgs: [ownerId, id, epoch],
    );
    return rows.isEmpty
        ? null
        : jsonDecode(cipher.decrypt(rows.single['payload'] as String))
              as Map<String, dynamic>;
  }

  @override
  Future<void> saveDraft(
    String id,
    int epoch,
    Map<String, dynamic>? draft,
  ) async {
    final cipher = await _cipher();
    if (draft == null) {
      await database.db.delete(
        'lab_agent_drafts',
        where: 'owner_id = ? AND agent_id = ?',
        whereArgs: [ownerId, id],
      );
    } else {
      await database.db.insert('lab_agent_drafts', {
        'owner_id': ownerId,
        'agent_id': id,
        'epoch': epoch,
        'payload': cipher.encrypt(jsonEncode(draft)),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
