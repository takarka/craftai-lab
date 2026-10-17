import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../schema/storage_schema_v1.dart';

enum StagingStatus {
  pending,
  committed,
  aborted,
}

/// Coordinates file writes with database records using two-phase staging commit.
final class FileStagingJournal {
  const FileStagingJournal();

  /// Begins a staging operation, writing a journal entry in the database.
  Future<void> recordStaging({
    required DatabaseExecutor db,
    required String id,
    required String ownerId,
    required String stagingPath,
    required String targetPath,
  }) async {
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      StorageSchemaV1.tableFileStagingJournal,
      {
        'id': id,
        'owner_id': ownerId,
        'staging_path': stagingPath,
        'target_path': targetPath,
        'status': StagingStatus.pending.name,
        'created_at_utc': nowUtc,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Atomically moves the staged file to target destination and marks journal committed.
  Future<void> commitStagedFile({
    required DatabaseExecutor db,
    required String id,
    required String stagingPath,
    required String targetPath,
  }) async {
    final stagingFile = File(stagingPath);
    if (!await stagingFile.exists()) {
      throw FileSystemException('Staged file does not exist at path: $stagingPath');
    }

    final targetDir = Directory(File(targetPath).parent.path);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    // Atomic move / rename
    await stagingFile.rename(targetPath);

    await db.update(
      StorageSchemaV1.tableFileStagingJournal,
      {'status': StagingStatus.committed.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Cleans up any interrupted or abandoned staging files on startup.
  Future<int> recoverInterruptedStaging(DatabaseExecutor db) async {
    final pendingEntries = await db.query(
      StorageSchemaV1.tableFileStagingJournal,
      where: 'status = ?',
      whereArgs: [StagingStatus.pending.name],
    );

    var cleanedCount = 0;
    for (final entry in pendingEntries) {
      final id = entry['id'] as String;
      final stagingPath = entry['staging_path'] as String;
      try {
        final file = File(stagingPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Suppress errors during cleanup of abandoned files
      }

      await db.update(
        StorageSchemaV1.tableFileStagingJournal,
        {'status': StagingStatus.aborted.name},
        where: 'id = ?',
        whereArgs: [id],
      );
      cleanedCount++;
    }
    return cleanedCount;
  }
}
