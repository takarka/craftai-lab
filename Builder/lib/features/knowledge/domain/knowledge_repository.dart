import 'dart:typed_data';
import 'knowledge_models.dart';

abstract class KnowledgeRepository {
  /// Returns all knowledge documents belonging to [ownerId].
  Future<List<KnowledgeDocument>> getDocuments(String ownerId);

  /// Returns a specific document by [docId] or null.
  Future<KnowledgeDocument?> getDocumentById(String ownerId, String docId);

  /// Returns all chunks belonging to [ownerId]. If [enabledOnly] is true,
  /// chunks from disabled documents are excluded.
  Future<List<KnowledgeChunk>> getChunksForOwner(String ownerId, {bool enabledOnly = true});

  /// Imports, hashes, parses, chunks, and indexes a new document file.
  /// Throws [DocumentProcessingException] on validation or extraction failure.
  Future<KnowledgeDocument> importDocument({
    required String ownerId,
    required String fileName,
    required Uint8List bytes,
    required DocumentFormat format,
  });

  /// Toggles search inclusion for a document without deleting its chunks.
  Future<void> toggleDocumentEnabled({
    required String ownerId,
    required String docId,
    required bool isEnabled,
  });

  /// Physically deletes document, its files from private disk, revisions, and chunks.
  Future<void> deleteDocument({
    required String ownerId,
    required String docId,
  });

  /// Performs hybrid semantic + lexical search across enabled documents for [ownerId].
  Future<KnowledgeSearchResult> searchKnowledge({
    required String ownerId,
    required String query,
    double? threshold,
  });
}
