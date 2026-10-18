import 'package:sqflite/sqflite.dart';

import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../domain/pending_action.dart';
import '../domain/tool_definition.dart';
import '../domain/tool_grant.dart';
import '../domain/tool_invocation.dart';
import '../domain/tools_registry.dart';
import '../domain/tools_repository.dart';

/// SQLite-backed persistent tools repository implementing F14-01, F14-05, F14-11.
class PersistentToolsRepository implements ToolsRepository {
  final StorageDatabase database;
  final Map<String, OsPermissionStatus> _osPermissions = {};

  PersistentToolsRepository({required this.database});

  Future<void> _ensureOpen() async {
    if (!database.isOpen) {
      await database.open();
    }
  }

  Future<Database> get _db async {
    await _ensureOpen();
    return database.db;
  }

  @override
  Future<List<ToolGrant>> getGrants(String ownerId) async {
    final db = await _db;
    final rows = await db.query(
      StorageSchemaV1.tableToolGrants,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    return rows.map((r) => ToolGrant.fromMap(r)).toList();
  }

  @override
  Future<ToolGrant?> getGrant(String ownerId, String toolName) async {
    final db = await _db;
    final rows = await db.query(
      StorageSchemaV1.tableToolGrants,
      where: 'owner_id = ? AND tool_name = ?',
      whereArgs: [ownerId, toolName],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ToolGrant.fromMap(rows.first);
  }

  @override
  Future<void> setGrant({
    required String ownerId,
    required String toolName,
    required bool isEnabled,
    String permissionScope = 'standard',
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();

    final existing = await getGrant(ownerId, toolName);
    final revision = (existing?.revision ?? 0) + 1;

    final grant = ToolGrant(
      ownerId: ownerId,
      toolName: toolName,
      isEnabled: isEnabled,
      permissionScope: permissionScope,
      revision: revision,
      updatedAtUtc: now,
    );

    await db.insert(
      StorageSchemaV1.tableToolGrants,
      grant.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> ensureDefaultGrants(String ownerId) async {
    final current = await getGrants(ownerId);
    if (current.isNotEmpty) return;

    final now = DateTime.now().toUtc();
    final db = await _db;

    await db.transaction((txn) async {
      for (final tool in ToolsRegistry.allTools) {
        // Web search is disabled by default per F14-09; calendar/notes/comm are enabled by default
        final defaultEnabled = tool.name != ToolsRegistry.webSearch;
        final grant = ToolGrant(
          ownerId: ownerId,
          toolName: tool.name,
          isEnabled: defaultEnabled,
          permissionScope: 'standard',
          revision: 1,
          updatedAtUtc: now,
        );
        await txn.insert(
          StorageSchemaV1.tableToolGrants,
          grant.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<PendingAction> createPendingAction(PendingAction action) async {
    final db = await _db;
    await db.insert(
      StorageSchemaV1.tablePendingActions,
      action.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return action;
  }

  @override
  Future<PendingAction?> getPendingAction(String invocationId) async {
    final db = await _db;
    final rows = await db.query(
      StorageSchemaV1.tablePendingActions,
      where: 'invocation_id = ?',
      whereArgs: [invocationId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PendingAction.fromMap(rows.first);
  }

  @override
  Future<List<PendingAction>> getPendingActions(
    String ownerId, {
    PendingActionStatus? status,
  }) async {
    final db = await _db;
    final whereClauses = <String>['owner_id = ?'];
    final whereArgs = <dynamic>[ownerId];

    if (status != null) {
      whereClauses.add('status = ?');
      whereArgs.add(status.id);
    }

    final rows = await db.query(
      StorageSchemaV1.tablePendingActions,
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'created_at_utc DESC',
    );
    return rows.map((r) => PendingAction.fromMap(r)).toList();
  }

  @override
  Future<void> updatePendingActionStatus({
    required String invocationId,
    required PendingActionStatus status,
  }) async {
    final db = await _db;
    await db.update(
      StorageSchemaV1.tablePendingActions,
      {'status': status.id},
      where: 'invocation_id = ?',
      whereArgs: [invocationId],
    );
  }

  @override
  Future<void> logInvocation(ToolInvocationRecord record) async {
    final db = await _db;
    await db.insert(
      StorageSchemaV1.tableToolInvocations,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<ToolInvocationRecord>> getInvocations(
    String ownerId, {
    int limit = 20,
  }) async {
    final db = await _db;
    final rows = await db.query(
      StorageSchemaV1.tableToolInvocations,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'started_at_utc DESC',
      limit: limit,
    );
    return rows.map((r) => ToolInvocationRecord.fromMap(r)).toList();
  }

  @override
  Future<OsPermissionStatus> getOsPermission(String toolName) async {
    return _osPermissions[toolName] ?? OsPermissionStatus.granted;
  }

  @override
  Future<void> setOsPermission(
    String toolName,
    OsPermissionStatus status,
  ) async {
    _osPermissions[toolName] = status;
  }
}

/// In-memory implementation of ToolsRepository for fast tests.
class InMemoryToolsRepository implements ToolsRepository {
  final Map<String, Map<String, ToolGrant>> _grants = {};
  final Map<String, PendingAction> _pendingActions = {};
  final List<ToolInvocationRecord> _invocations = [];
  final Map<String, OsPermissionStatus> _osPermissions = {};

  @override
  Future<List<ToolGrant>> getGrants(String ownerId) async {
    return _grants[ownerId]?.values.toList() ?? [];
  }

  @override
  Future<ToolGrant?> getGrant(String ownerId, String toolName) async {
    return _grants[ownerId]?[toolName];
  }

  @override
  Future<void> setGrant({
    required String ownerId,
    required String toolName,
    required bool isEnabled,
    String permissionScope = 'standard',
  }) async {
    final userGrants = _grants.putIfAbsent(ownerId, () => {});
    final existing = userGrants[toolName];
    final revision = (existing?.revision ?? 0) + 1;
    userGrants[toolName] = ToolGrant(
      ownerId: ownerId,
      toolName: toolName,
      isEnabled: isEnabled,
      permissionScope: permissionScope,
      revision: revision,
      updatedAtUtc: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> ensureDefaultGrants(String ownerId) async {
    if (_grants.containsKey(ownerId) && _grants[ownerId]!.isNotEmpty) return;
    final now = DateTime.now().toUtc();
    final userGrants = _grants.putIfAbsent(ownerId, () => {});
    for (final tool in ToolsRegistry.allTools) {
      final defaultEnabled = tool.name != ToolsRegistry.webSearch;
      userGrants[tool.name] = ToolGrant(
        ownerId: ownerId,
        toolName: tool.name,
        isEnabled: defaultEnabled,
        permissionScope: 'standard',
        revision: 1,
        updatedAtUtc: now,
      );
    }
  }

  @override
  Future<PendingAction> createPendingAction(PendingAction action) async {
    _pendingActions[action.invocationId] = action;
    return action;
  }

  @override
  Future<PendingAction?> getPendingAction(String invocationId) async {
    return _pendingActions[invocationId];
  }

  @override
  Future<List<PendingAction>> getPendingActions(
    String ownerId, {
    PendingActionStatus? status,
  }) async {
    final list = _pendingActions.values.where((a) => a.ownerId == ownerId);
    if (status != null) {
      return list.where((a) => a.status == status).toList();
    }
    return list.toList();
  }

  @override
  Future<void> updatePendingActionStatus({
    required String invocationId,
    required PendingActionStatus status,
  }) async {
    final existing = _pendingActions[invocationId];
    if (existing != null) {
      _pendingActions[invocationId] = existing.copyWith(status: status);
    }
  }

  @override
  Future<void> logInvocation(ToolInvocationRecord record) async {
    _invocations.add(record);
  }

  @override
  Future<List<ToolInvocationRecord>> getInvocations(
    String ownerId, {
    int limit = 20,
  }) async {
    return _invocations.where((i) => i.ownerId == ownerId).take(limit).toList();
  }

  @override
  Future<OsPermissionStatus> getOsPermission(String toolName) async {
    return _osPermissions[toolName] ?? OsPermissionStatus.granted;
  }

  @override
  Future<void> setOsPermission(
    String toolName,
    OsPermissionStatus status,
  ) async {
    _osPermissions[toolName] = status;
  }
}
