import 'package:flutter/foundation.dart';

enum DocumentFormat {
  pdf('pdf', 'PDF'),
  docx('docx', 'DOCX'),
  txt('txt', 'TXT');

  final String extension;
  final String label;

  const DocumentFormat(this.extension, this.label);

  static DocumentFormat? fromExtension(String ext) {
    final clean = ext.toLowerCase().replaceAll('.', '').trim();
    for (final f in values) {
      if (f.extension == clean) return f;
    }
    return null;
  }
}

enum DocumentProcessingStatus {
  pending('pending', 'В очереди'),
  indexing('indexing', 'Индексация...'),
  ready('ready', 'Готов к поиску'),
  failed('failed', 'Ошибка обработки'),
  empty('empty', 'Нет текста');

  final String dbValue;
  final String label;

  const DocumentProcessingStatus(this.dbValue, this.label);

  static DocumentProcessingStatus fromDbValue(String value) {
    for (final s in values) {
      if (s.dbValue == value) return s;
    }
    return DocumentProcessingStatus.failed;
  }
}

@immutable
class KnowledgeDocument {
  final String id;
  final String ownerId;
  final String contentHash;
  final String fileName;
  final DocumentFormat fileFormat;
  final int fileSizeBytes;
  final bool isEnabled;
  final DocumentProcessingStatus indexStatus;
  final String? errorMessage;
  final int chunksCount;
  final DateTime createdAtUtc;

  const KnowledgeDocument({
    required this.id,
    required this.ownerId,
    required this.contentHash,
    required this.fileName,
    required this.fileFormat,
    required this.fileSizeBytes,
    this.isEnabled = true,
    this.indexStatus = DocumentProcessingStatus.ready,
    this.errorMessage,
    this.chunksCount = 0,
    required this.createdAtUtc,
  });

  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes Б';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} КБ';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  KnowledgeDocument copyWith({
    String? id,
    String? ownerId,
    String? contentHash,
    String? fileName,
    DocumentFormat? fileFormat,
    int? fileSizeBytes,
    bool? isEnabled,
    DocumentProcessingStatus? indexStatus,
    String? errorMessage,
    int? chunksCount,
    DateTime? createdAtUtc,
  }) {
    return KnowledgeDocument(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      contentHash: contentHash ?? this.contentHash,
      fileName: fileName ?? this.fileName,
      fileFormat: fileFormat ?? this.fileFormat,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      isEnabled: isEnabled ?? this.isEnabled,
      indexStatus: indexStatus ?? this.indexStatus,
      errorMessage: errorMessage ?? this.errorMessage,
      chunksCount: chunksCount ?? this.chunksCount,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'content_hash': contentHash,
    'file_name': fileName,
    'file_format': fileFormat.extension,
    'file_size_bytes': fileSizeBytes,
    'is_enabled': isEnabled,
    'index_status': indexStatus.dbValue,
    'error_message': errorMessage,
    'chunks_count': chunksCount,
    'created_at_utc': createdAtUtc.toIso8601String(),
  };

  factory KnowledgeDocument.fromJson(Map<String, dynamic> json) {
    return KnowledgeDocument(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String? ?? '',
      contentHash: json['content_hash'] as String? ?? '',
      fileName: json['file_name'] as String? ?? 'Документ',
      fileFormat:
          DocumentFormat.fromExtension(
            json['file_format'] as String? ?? 'txt',
          ) ??
          DocumentFormat.txt,
      fileSizeBytes: json['file_size_bytes'] as int? ?? 0,
      isEnabled: (json['is_enabled'] is bool)
          ? json['is_enabled'] as bool
          : (json['is_enabled'] as int? ?? 1) == 1,
      indexStatus: DocumentProcessingStatus.fromDbValue(
        json['index_status'] as String? ?? 'ready',
      ),
      errorMessage: json['error_message'] as String?,
      chunksCount: json['chunks_count'] as int? ?? 0,
      createdAtUtc:
          DateTime.tryParse(json['created_at_utc'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

@immutable
class DocumentRevision {
  final String id;
  final String documentId;
  final String ownerId;
  final String parserVersion;
  final String embeddingModelId;
  final String textContent;
  final String? blobPath;
  final DateTime createdAtUtc;

  const DocumentRevision({
    required this.id,
    required this.documentId,
    required this.ownerId,
    this.parserVersion = 'v1.0',
    this.embeddingModelId = 'on-device-hybrid-v1',
    required this.textContent,
    this.blobPath,
    required this.createdAtUtc,
  });
}

@immutable
class KnowledgeChunk {
  final String id;
  final String revisionId;
  final String documentId;
  final String documentName;
  final String ownerId;
  final int chunkIndex;
  final String chunkText;
  final int pageNumber;
  final int byteOffset;
  final List<double> embeddingVector;
  final Map<String, dynamic> metadata;

  const KnowledgeChunk({
    required this.id,
    required this.revisionId,
    required this.documentId,
    this.documentName = '',
    required this.ownerId,
    required this.chunkIndex,
    required this.chunkText,
    this.pageNumber = 1,
    this.byteOffset = 0,
    this.embeddingVector = const [],
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'revision_id': revisionId,
    'document_id': documentId,
    'document_name': documentName,
    'owner_id': ownerId,
    'chunk_index': chunkIndex,
    'chunk_text': chunkText,
    'page_number': pageNumber,
    'byte_offset': byteOffset,
    'embedding_vector': embeddingVector,
    'metadata': metadata,
  };

  factory KnowledgeChunk.fromJson(Map<String, dynamic> json) {
    final rawVec = json['embedding_vector'] as List<dynamic>? ?? [];
    return KnowledgeChunk(
      id: json['id'] as String,
      revisionId: json['revision_id'] as String,
      documentId: json['document_id'] as String? ?? '',
      documentName: json['document_name'] as String? ?? '',
      ownerId: json['owner_id'] as String? ?? '',
      chunkIndex: json['chunk_index'] as int? ?? 0,
      chunkText: json['chunk_text'] as String? ?? '',
      pageNumber: json['page_number'] as int? ?? 1,
      byteOffset: json['byte_offset'] as int? ?? 0,
      embeddingVector: rawVec.map((e) => (e as num).toDouble()).toList(),
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }
}

@immutable
class SearchResultChunk {
  final KnowledgeChunk chunk;
  final double score; // 0.0 .. 1.0
  final bool isAboveThreshold;

  const SearchResultChunk({
    required this.chunk,
    required this.score,
    required this.isAboveThreshold,
  });

  String get scorePercentage => '${(score * 100).toStringAsFixed(0)}%';
}

@immutable
class KnowledgeSearchResult {
  final String query;
  final List<SearchResultChunk> matches;
  final bool hasRelevantMatches;
  final int totalScannedChunks;
  final int searchDurationMs;

  const KnowledgeSearchResult({
    required this.query,
    required this.matches,
    required this.hasRelevantMatches,
    required this.totalScannedChunks,
    required this.searchDurationMs,
  });

  List<String> get matchedChunkTexts => matches
      .where((m) => m.isAboveThreshold)
      .map((m) => m.chunk.chunkText)
      .toList();
}
