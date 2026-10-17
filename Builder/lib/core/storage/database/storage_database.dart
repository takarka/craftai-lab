import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../schema/storage_schema_v1.dart';

class StorageCorruptionException implements Exception {
  const StorageCorruptionException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => 'StorageCorruptionException: $message${cause != null ? ' (Cause: $cause)' : ''}';
}

class MigrationFailedException implements Exception {
  const MigrationFailedException(this.fromVersion, this.toVersion, this.message, [this.cause]);
  final int fromVersion;
  final int toVersion;
  final String message;
  final Object? cause;

  @override
  String toString() => 'MigrationFailedException ($fromVersion -> $toVersion): $message';
}

class StorageQuotaExceededException implements Exception {
  const StorageQuotaExceededException(this.message);
  final String message;

  @override
  String toString() => 'StorageQuotaExceededException: $message';
}

/// Manages database lifecycle, migrations, and transactional integrity.
final class StorageDatabase {
  StorageDatabase({
    required this.databasePath,
    DatabaseFactory? databaseFactory,
  }) : _databaseFactory = databaseFactory ?? databaseFactorySqflitePlugin;

  final String databasePath;
  final DatabaseFactory _databaseFactory;
  Database? _db;

  bool get isOpen => _db != null && _db!.isOpen;

  Database get db {
    final active = _db;
    if (active == null || !active.isOpen) {
      throw StateError('StorageDatabase is not open. Call open() first.');
    }
    return active;
  }

  Future<void> open() async {
    if (isOpen) return;

    final dbDir = Directory(p.dirname(databasePath));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }

    try {
      _db = await _databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: StorageSchemaV1.version,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON;');
          },
          onCreate: (db, version) async {
            for (final statement in StorageSchemaV1.createStatements) {
              await db.execute(statement);
            }
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            await _runMigrations(db, oldVersion, newVersion);
          },
          onDowngrade: (db, oldVersion, newVersion) {
            throw MigrationFailedException(
              oldVersion,
              newVersion,
              'Downgrading database schema is prohibited to protect user data.',
            );
          },
        ),
      );
    } on MigrationFailedException {
      rethrow;
    } catch (e) {
      // Never silently delete the database on corruption!
      throw StorageCorruptionException(
        'Database file at "$databasePath" is corrupt or inaccessible.',
        e,
      );
    }
  }

  Future<void> _runMigrations(Database db, int oldVersion, int newVersion) async {
    // Before running migrations, create a backup copy if possible
    await _createMigrationBackup(oldVersion);

    try {
      // Future migrations (v1 -> v2, etc.) will be added sequentially here.
      // Schema v1 is initial, so no migrations needed yet.
    } catch (e) {
      throw MigrationFailedException(
        oldVersion,
        newVersion,
        'Migration failed. Database retained for recovery.',
        e,
      );
    }
  }

  Future<void> _createMigrationBackup(int fromVersion) async {
    try {
      final file = File(databasePath);
      if (await file.exists()) {
        final backupPath = '$databasePath.v$fromVersion.bak';
        await file.copy(backupPath);
      }
    } catch (_) {
      // If backup copy fails, continue or throw depending on policy
    }
  }

  /// Runs an atomic transaction with automatic rollback on error.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    return await db.transaction<T>(action);
  }

  /// Closes database connection safely.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
  }
}
