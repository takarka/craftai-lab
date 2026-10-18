import 'dart:io';
import '../database/storage_database.dart';
import '../files/file_staging_journal.dart';
import '../schema/storage_schema_v1.dart';
import '../security/secure_key_storage.dart';

class ActiveWorkspaceInfo {
  const ActiveWorkspaceInfo({
    required this.ownerId,
    required this.installationId,
    required this.workspaceEpoch,
    required this.schemaVersion,
  });

  final String ownerId;
  final String installationId;
  final int workspaceEpoch;
  final int schemaVersion;
}

final class WorkspaceStorageService {
  WorkspaceStorageService({
    required this.database,
    required this.keyStorage,
    required this.installationId,
    FileStagingJournal? stagingJournal,
  }) : stagingJournal = stagingJournal ?? const FileStagingJournal();

  final StorageDatabase database;
  final SecureKeyStorage keyStorage;
  final String installationId;
  final FileStagingJournal stagingJournal;

  String? _activeOwnerId;
  int? _activeEpoch;
  final Map<String, dynamic> _inMemoryCache = {};

  String? get activeOwnerId => _activeOwnerId;
  int? get activeEpoch => _activeEpoch;
  bool get hasActiveWorkspace => _activeOwnerId != null;

  /// In-memory cache accessible only for active owner.
  Map<String, dynamic> get inMemoryCache {
    if (_activeOwnerId == null) {
      throw StateError(
        'Cannot access in-memory cache without an active workspace.',
      );
    }
    return _inMemoryCache;
  }

  /// Opens or switches workspace to [ownerId].
  /// Guarantees that any previous owner's session and caches are wiped.
  Future<ActiveWorkspaceInfo> openWorkspace({required String ownerId}) async {
    if (ownerId.trim().isEmpty) {
      throw ArgumentError('Owner ID cannot be empty.');
    }

    // If switching owners, close previous workspace and purge caches first
    if (_activeOwnerId != null && _activeOwnerId != ownerId) {
      await closeActiveWorkspace();
    }

    if (!database.isOpen) {
      await database.open();
    }

    // Recover any abandoned staging files on database open
    await stagingJournal.recoverInterruptedStaging(database.db);

    // Retrieve or initialize workspace record
    final rows = await database.db.query(
      StorageSchemaV1.tableWorkspaces,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );

    int epoch;
    int schemaVer;

    if (rows.isEmpty) {
      // First-time workspace for this owner
      epoch = 1;
      schemaVer = StorageSchemaV1.version;
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      await database.db.insert(StorageSchemaV1.tableWorkspaces, {
        'owner_id': ownerId,
        'installation_id': installationId,
        'schema_version': schemaVer,
        'workspace_epoch': epoch,
        'created_at_utc': nowUtc,
        'updated_at_utc': nowUtc,
      });
    } else {
      epoch = rows.first['workspace_epoch'] as int;
      schemaVer = rows.first['schema_version'] as int;
    }

    _activeOwnerId = ownerId;
    _activeEpoch = epoch;
    _inMemoryCache.clear();

    return ActiveWorkspaceInfo(
      ownerId: ownerId,
      installationId: installationId,
      workspaceEpoch: epoch,
      schemaVersion: schemaVer,
    );
  }

  /// Closes the active workspace, clearing memory caches, active epoch and owner ID.
  Future<void> closeActiveWorkspace() async {
    _activeOwnerId = null;
    _activeEpoch = null;
    _inMemoryCache.clear();
  }

  /// Advances workspaceEpoch, invalidating any concurrent or stale write operations.
  Future<int> bumpWorkspaceEpoch({required String ownerId}) async {
    if (_activeOwnerId != ownerId) {
      throw StateError('Cannot bump epoch for an inactive owner.');
    }

    final newEpoch = (_activeEpoch ?? 0) + 1;
    final nowUtc = DateTime.now().toUtc().toIso8601String();

    await database.db.update(
      StorageSchemaV1.tableWorkspaces,
      {'workspace_epoch': newEpoch, 'updated_at_utc': nowUtc},
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );

    _activeEpoch = newEpoch;
    return newEpoch;
  }

  /// Completely purges all stored data for [ownerId] (for account deletion or full reset).
  Future<void> purgeOwnerData({
    required String ownerId,
    String? ownerFilesDir,
  }) async {
    if (ownerId.trim().isEmpty) return;

    if (_activeOwnerId == ownerId) {
      await closeActiveWorkspace();
    }

    if (!database.isOpen) {
      await database.open();
    }

    await database.transaction((txn) async {
      await txn.delete(
        StorageSchemaV1.tableWorkspaces,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      // Cascades delete related records in teacher_preferences, configurations, etc.
      // Explicitly delete non-foreign key tables if any:
      await txn.delete(
        StorageSchemaV1.tableFileStagingJournal,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      await txn.delete(
        StorageSchemaV1.tablePolicyAcknowledgments,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
    });

    if (ownerFilesDir != null) {
      final dir = Directory(ownerFilesDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  }
}
