import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../domain/chunker.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_repository.dart';
import '../domain/local_embedder.dart';
import '../domain/text_extractor.dart';

class PersistentKnowledgeRepository implements KnowledgeRepository {
  final StorageDatabase database;
  final String? baseStorageDir;
  final SentenceWindowChunker chunker;
  final LocalHybridSearchEngine searchEngine;

  PersistentKnowledgeRepository({
    required this.database,
    this.baseStorageDir,
    SentenceWindowChunker? chunker,
    LocalHybridSearchEngine? searchEngine,
  })  : chunker = chunker ?? const SentenceWindowChunker(),
        searchEngine = searchEngine ?? const LocalHybridSearchEngine();

  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB per F12-01

  Future<void> _ensureOpen() async {
    if (!database.isOpen) {
      await database.open();
    }
  }

  Future<String> _resolveBaseDir() async {
    if (baseStorageDir != null) return baseStorageDir!;
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  @override
  Future<List<KnowledgeDocument>> getDocuments(String ownerId) async {
    await _ensureOpen();

    final rows = await database.db.query(
      StorageSchemaV1.tableKnowledgeDocuments,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'created_at_utc DESC',
    );

    if (rows.isEmpty) return const [];

    // Also get chunk counts per document
    final chunkCountsRows = await database.db.rawQuery('''
      SELECT r.document_id, COUNT(c.id) as chunk_count
      FROM ${StorageSchemaV1.tableKnowledgeChunks} c
      JOIN ${StorageSchemaV1.tableDocumentRevisions} r ON c.revision_id = r.id
      WHERE c.owner_id = ?
      GROUP BY r.document_id
    ''', [ownerId]);

    final chunkCounts = <String, int>{};
    for (final r in chunkCountsRows) {
      final docId = r['document_id'] as String?;
      final count = r['chunk_count'] as int?;
      if (docId != null && count != null) {
        chunkCounts[docId] = count;
      }
    }

    return rows.map((row) {
      final doc = KnowledgeDocument.fromJson(row);
      final count = chunkCounts[doc.id] ?? 0;
      return doc.copyWith(chunksCount: count);
    }).toList();
  }

  @override
  Future<KnowledgeDocument?> getDocumentById(String ownerId, String docId) async {
    await _ensureOpen();

    final rows = await database.db.query(
      StorageSchemaV1.tableKnowledgeDocuments,
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, docId],
    );

    if (rows.isEmpty) return null;
    return KnowledgeDocument.fromJson(rows.first);
  }

  @override
  Future<List<KnowledgeChunk>> getChunksForOwner(String ownerId, {bool enabledOnly = true}) async {
    await _ensureOpen();

    final sql = '''
      SELECT c.*, d.file_name as doc_name, d.id as doc_id, d.is_enabled
      FROM ${StorageSchemaV1.tableKnowledgeChunks} c
      JOIN ${StorageSchemaV1.tableDocumentRevisions} r ON c.revision_id = r.id
      JOIN ${StorageSchemaV1.tableKnowledgeDocuments} d ON r.document_id = d.id
      WHERE c.owner_id = ?
      ${enabledOnly ? 'AND d.is_enabled = 1' : ''}
      ORDER BY c.revision_id, c.chunk_index ASC
    ''';

    final rows = await database.db.rawQuery(sql, [ownerId]);

    return rows.map((row) {
      List<double> vector = const [];
      Map<String, dynamic> metadata = const {};

      final metaJsonStr = row['embedding_metadata_json'] as String?;
      if (metaJsonStr != null && metaJsonStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(metaJsonStr) as Map<String, dynamic>;
          final rawVec = decoded['vector'] as List<dynamic>? ?? [];
          vector = rawVec.map((e) => (e as num).toDouble()).toList();
          metadata = decoded['metadata'] as Map<String, dynamic>? ?? {};
        } catch (_) {}
      }

      return KnowledgeChunk(
        id: row['id'] as String,
        revisionId: row['revision_id'] as String,
        documentId: row['doc_id'] as String? ?? '',
        documentName: row['doc_name'] as String? ?? '',
        ownerId: row['owner_id'] as String,
        chunkIndex: row['chunk_index'] as int,
        chunkText: row['chunk_text'] as String,
        pageNumber: row['page_number'] as int? ?? 1,
        byteOffset: row['byte_offset'] as int? ?? 0,
        embeddingVector: vector,
        metadata: metadata,
      );
    }).toList();
  }

  @override
  Future<KnowledgeDocument> importDocument({
    required String ownerId,
    required String fileName,
    required Uint8List bytes,
    required DocumentFormat format,
  }) async {
    await _ensureOpen();

    // 1. Validate max file size (10 MB per F12-01)
    if (bytes.length > maxFileSizeBytes) {
      throw const DocumentProcessingException(
        code: 'size_exceeded',
        message: 'Размер файла превышает лимит в 10 МБ.',
      );
    }

    if (bytes.isEmpty) {
      throw const DocumentProcessingException(
        code: 'empty_file',
        message: 'Файл пуст (0 байт).',
      );
    }

    // 2. Calculate content hash (SHA-256) per F12-02
    final hashDigest = sha256.convert(bytes);
    final contentHash = hashDigest.toString();

    // Check for duplicate content for this owner
    final existingRows = await database.db.query(
      StorageSchemaV1.tableKnowledgeDocuments,
      where: 'owner_id = ? AND content_hash = ?',
      whereArgs: [ownerId, contentHash],
    );

    if (existingRows.isNotEmpty) {
      // Return already existing document to prevent duplicate storage
      return KnowledgeDocument.fromJson(existingRows.first);
    }

    // 3. Extract text outside UI isolate
    final extracted = await TextExtractor.extract(
      bytes: bytes,
      format: format,
      fileName: fileName,
    );

    // 4. Stable doc and rev IDs
    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();
    final docId = 'doc_${now.millisecondsSinceEpoch}_${contentHash.substring(0, 8)}';
    final revId = 'rev_${now.millisecondsSinceEpoch}';

    // 5. Store binary copy safely in private workspace directory (F12-02)
    final baseDir = await _resolveBaseDir();
    final safeFileName = _sanitizeFileName(fileName);
    final knowledgeDir = Directory(p.join(baseDir, 'workspaces', ownerId, 'knowledge'));
    if (!await knowledgeDir.exists()) {
      await knowledgeDir.create(recursive: true);
    }

    final blobPath = p.join(knowledgeDir.path, '$docId.${format.extension}');
    final blobFile = File(blobPath);
    await blobFile.writeAsBytes(bytes, flush: true);

    // 6. Sentence-window chunking (F12-05)
    final rawChunks = chunker.chunkDocument(
      extracted: extracted,
      documentId: docId,
      revisionId: revId,
      ownerId: ownerId,
      documentName: safeFileName,
    );

    // 7. Embed chunks (F12-06)
    final chunksWithEmbeddings = rawChunks.map((c) {
      final vector = searchEngine.embedText(c.chunkText);
      return KnowledgeChunk(
        id: c.id,
        revisionId: c.revisionId,
        documentId: c.documentId,
        documentName: c.documentName,
        ownerId: c.ownerId,
        chunkIndex: c.chunkIndex,
        chunkText: c.chunkText,
        pageNumber: c.pageNumber,
        byteOffset: c.byteOffset,
        embeddingVector: vector,
        metadata: c.metadata,
      );
    }).toList();

    // 8. Transactional persistence in SQLite
    await database.transaction((txn) async {
      // Insert Document
      await txn.insert(
        StorageSchemaV1.tableKnowledgeDocuments,
        {
          'id': docId,
          'owner_id': ownerId,
          'content_hash': contentHash,
          'file_name': safeFileName,
          'file_format': format.extension,
          'file_size_bytes': bytes.length,
          'is_enabled': 1,
          'index_status': DocumentProcessingStatus.ready.dbValue,
          'created_at_utc': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Insert Revision
      await txn.insert(
        StorageSchemaV1.tableDocumentRevisions,
        {
          'id': revId,
          'document_id': docId,
          'owner_id': ownerId,
          'parser_version': 'v1.0',
          'embedding_model_id': 'on-device-hybrid-v1',
          'text_content': extracted.fullText,
          'blob_path': blobPath,
          'created_at_utc': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Insert Chunks
      final batch = txn.batch();
      for (final chunk in chunksWithEmbeddings) {
        final metaJson = jsonEncode({
          'vector': chunk.embeddingVector,
          'metadata': chunk.metadata,
        });

        batch.insert(
          StorageSchemaV1.tableKnowledgeChunks,
          {
            'id': chunk.id,
            'revision_id': revId,
            'owner_id': ownerId,
            'chunk_index': chunk.chunkIndex,
            'chunk_text': chunk.chunkText,
            'page_number': chunk.pageNumber,
            'byte_offset': chunk.byteOffset,
            'embedding_metadata_json': metaJson,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });

    return KnowledgeDocument(
      id: docId,
      ownerId: ownerId,
      contentHash: contentHash,
      fileName: safeFileName,
      fileFormat: format,
      fileSizeBytes: bytes.length,
      isEnabled: true,
      indexStatus: DocumentProcessingStatus.ready,
      chunksCount: chunksWithEmbeddings.length,
      createdAtUtc: now,
    );
  }

  @override
  Future<void> toggleDocumentEnabled({
    required String ownerId,
    required String docId,
    required bool isEnabled,
  }) async {
    await _ensureOpen();

    await database.db.update(
      StorageSchemaV1.tableKnowledgeDocuments,
      {'is_enabled': isEnabled ? 1 : 0},
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, docId],
    );
  }

  @override
  Future<void> deleteDocument({
    required String ownerId,
    required String docId,
  }) async {
    await _ensureOpen();

    // 1. Locate revisions to delete physical files
    final revRows = await database.db.query(
      StorageSchemaV1.tableDocumentRevisions,
      columns: ['blob_path'],
      where: 'document_id = ? AND owner_id = ?',
      whereArgs: [docId, ownerId],
    );

    var fileDeletionFailed = false;
    for (final r in revRows) {
      final blobPath = r['blob_path'] as String?;
      if (blobPath != null) {
        final f = File(blobPath);
        if (await f.exists()) {
          try {
            await f.delete();
          } on FileSystemException {
            fileDeletionFailed = true;
          }
        }
      }
    }

    if (fileDeletionFailed) {
      // Keep the source/index records available for retry, but prevent their
      // derived content from entering new prompts after a partial file failure.
      await database.db.update(
        StorageSchemaV1.tableKnowledgeDocuments,
        {'is_enabled': 0},
        where: 'id = ? AND owner_id = ?',
        whereArgs: [docId, ownerId],
      );
      throw const KnowledgeFileDeletionException();
    }

    // 2. Delete from DB in transaction (foreign key cascade removes revisions and chunks)
    await database.transaction((txn) async {
      final revIdRows = await txn.query(
        StorageSchemaV1.tableDocumentRevisions,
        columns: ['id'],
        where: 'document_id = ? AND owner_id = ?',
        whereArgs: [docId, ownerId],
      );

      final revIds = revIdRows.map((r) => r['id'] as String).toList();
      for (final rid in revIds) {
        await txn.delete(
          StorageSchemaV1.tableKnowledgeChunks,
          where: 'revision_id = ? AND owner_id = ?',
          whereArgs: [rid, ownerId],
        );
      }

      await txn.delete(
        StorageSchemaV1.tableDocumentRevisions,
        where: 'document_id = ? AND owner_id = ?',
        whereArgs: [docId, ownerId],
      );

      await txn.delete(
        StorageSchemaV1.tableKnowledgeDocuments,
        where: 'id = ? AND owner_id = ?',
        whereArgs: [docId, ownerId],
      );
    });
  }

  @override
  Future<KnowledgeSearchResult> searchKnowledge({
    required String ownerId,
    required String query,
    double? threshold,
  }) async {
    final chunks = await getChunksForOwner(ownerId, enabledOnly: true);
    return searchEngine.search(
      query: query,
      chunks: chunks,
      thresholdOverride: threshold,
    );
  }

  String _sanitizeFileName(String name) {
    // Preserve letters, numbers, dots, dashes, underscores, spaces
    return name.replaceAll(RegExp(r'[^\w\s\.\-_а-яА-ЯёЁ]'), '_').trim();
  }
}

class KnowledgeFileDeletionException implements Exception {
  const KnowledgeFileDeletionException();

  @override
  String toString() => 'Не удалось физически удалить файл. Документ отключён; повторите удаление.';
}
