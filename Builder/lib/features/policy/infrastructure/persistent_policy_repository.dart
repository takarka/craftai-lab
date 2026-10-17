import 'package:sqflite/sqflite.dart';
import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../domain/policy_repository.dart';

final class PersistentPolicyRepository implements PolicyRepository {
  PersistentPolicyRepository({required this.database});

  final StorageDatabase database;

  @override
  Future<bool> isPolicyAcknowledged({
    required String ownerId,
    required String policyId,
  }) async {
    final ack = await getAcknowledgment(ownerId: ownerId, policyId: policyId);
    return ack != null;
  }

  @override
  Future<PolicyAcknowledgment?> getAcknowledgment({
    required String ownerId,
    required String policyId,
  }) async {
    if (!database.isOpen) {
      await database.open();
    }

    final rows = await database.db.query(
      StorageSchemaV1.tablePolicyAcknowledgments,
      where: 'owner_id = ? AND policy_id = ?',
      whereArgs: [ownerId, policyId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    return PolicyAcknowledgment(
      ownerId: row['owner_id'] as String,
      policyId: row['policy_id'] as String,
      policyVersion: row['policy_version'] as String,
      acknowledgedAtUtc: DateTime.parse(row['acknowledged_at_utc'] as String),
    );
  }

  @override
  Future<void> acknowledgePolicy({
    required String ownerId,
    required String policyId,
    required String policyVersion,
  }) async {
    if (!database.isOpen) {
      await database.open();
    }

    final nowUtc = DateTime.now().toUtc().toIso8601String();

    await database.db.insert(
      StorageSchemaV1.tablePolicyAcknowledgments,
      {
        'owner_id': ownerId,
        'policy_id': policyId,
        'policy_version': policyVersion,
        'acknowledged_at_utc': nowUtc,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

final class InMemoryPolicyRepository implements PolicyRepository {
  final Map<String, PolicyAcknowledgment> _acknowledgments = {};

  String _key(String ownerId, String policyId) => '$ownerId::$policyId';

  @override
  Future<bool> isPolicyAcknowledged({
    required String ownerId,
    required String policyId,
  }) async {
    return _acknowledgments.containsKey(_key(ownerId, policyId));
  }

  @override
  Future<PolicyAcknowledgment?> getAcknowledgment({
    required String ownerId,
    required String policyId,
  }) async {
    return _acknowledgments[_key(ownerId, policyId)];
  }

  @override
  Future<void> acknowledgePolicy({
    required String ownerId,
    required String policyId,
    required String policyVersion,
  }) async {
    _acknowledgments[_key(ownerId, policyId)] = PolicyAcknowledgment(
      ownerId: ownerId,
      policyId: policyId,
      policyVersion: policyVersion,
      acknowledgedAtUtc: DateTime.now().toUtc(),
    );
  }

  void clear() {
    _acknowledgments.clear();
  }
}
