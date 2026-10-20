import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../domain/document_work.dart';

/// Owner-scoped store of document tasks.
abstract class DocumentWorkRepository {
  Future<List<DocumentWork>> list(String ownerId);
  Future<DocumentWork?> get(String ownerId, String id);
  Future<void> save(String ownerId, DocumentWork work);
  Future<void> delete(String ownerId, String id);
}

class InMemoryDocumentWorkRepository implements DocumentWorkRepository {
  final _rows = <String, Map<String, DocumentWork>>{};

  @override
  Future<List<DocumentWork>> list(String ownerId) async =>
      (_rows[ownerId]?.values.toList() ?? [])
        ..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));

  @override
  Future<DocumentWork?> get(String ownerId, String id) async =>
      _rows[ownerId]?[id];

  @override
  Future<void> save(String ownerId, DocumentWork work) async =>
      _rows.putIfAbsent(ownerId, () => {})[work.id] = work;

  @override
  Future<void> delete(String ownerId, String id) async =>
      _rows[ownerId]?.remove(id);
}

class PersistentDocumentWorkRepository implements DocumentWorkRepository {
  PersistentDocumentWorkRepository({required this.database});
  final StorageDatabase database;

  Future<Database> get _db async {
    if (!database.isOpen) await database.open();
    return database.db;
  }

  @override
  Future<List<DocumentWork>> list(String ownerId) async {
    final rows = await (await _db).query(
      StorageSchemaV1.tableDocumentWork,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'created_at_utc DESC',
    );
    return rows.map(DocumentWork.fromRow).toList();
  }

  @override
  Future<DocumentWork?> get(String ownerId, String id) async {
    final rows = await (await _db).query(
      StorageSchemaV1.tableDocumentWork,
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, id],
    );
    return rows.isEmpty ? null : DocumentWork.fromRow(rows.first);
  }

  @override
  Future<void> save(String ownerId, DocumentWork work) async {
    await (await _db).insert(
      StorageSchemaV1.tableDocumentWork,
      work.toRow(ownerId),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String ownerId, String id) async {
    await (await _db).delete(
      StorageSchemaV1.tableDocumentWork,
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, id],
    );
  }
}

/// Temporary client copy of a picked file, kept only until the server has it.
abstract class DocumentStagingStore {
  /// Writes [bytes] and returns the path of the staged copy.
  Future<String> write(String ownerId, String workId, String fileName, List<int> bytes);
  Future<List<int>?> read(String path);
  Future<void> delete(String ownerId, String workId);
  Future<void> deleteOwner(String ownerId);
}

class FileDocumentStagingStore implements DocumentStagingStore {
  FileDocumentStagingStore(this.rootProvider);

  /// Directory that holds all staged uploads, e.g. under app support.
  final Future<Directory> Function() rootProvider;

  String _segment(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<Directory> _ownerDir(String ownerId) async =>
      Directory(p.join((await rootProvider()).path, _segment(ownerId)));

  @override
  Future<String> write(String ownerId, String workId, String fileName, List<int> bytes) async {
    final dir = Directory(p.join((await _ownerDir(ownerId)).path, _segment(workId)));
    await dir.create(recursive: true);
    // The original name is only kept in the database; the copy gets a fixed name.
    final file = File(p.join(dir.path, 'source.bin'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<List<int>?> read(String path) async {
    final file = File(path);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> delete(String ownerId, String workId) async {
    final dir = Directory(p.join((await _ownerDir(ownerId)).path, _segment(workId)));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<void> deleteOwner(String ownerId) async {
    final dir = await _ownerDir(ownerId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// For web and tests that need no disk.
class InMemoryDocumentStagingStore implements DocumentStagingStore {
  final files = <String, List<int>>{};

  @override
  Future<String> write(String ownerId, String workId, String fileName, List<int> bytes) async {
    final path = 'mem://$ownerId/$workId';
    files[path] = bytes;
    return path;
  }

  @override
  Future<List<int>?> read(String path) async => files[path];

  @override
  Future<void> delete(String ownerId, String workId) async =>
      files.remove('mem://$ownerId/$workId');

  @override
  Future<void> deleteOwner(String ownerId) async =>
      files.removeWhere((path, _) => path.startsWith('mem://$ownerId/'));
}
