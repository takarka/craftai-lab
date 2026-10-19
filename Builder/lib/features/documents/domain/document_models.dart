/// Wire models of the Builder file contract (EB-00/EB-02). Parsing is strict:
/// a value outside the contract is a [FormatException], never silently accepted.
library;

const maxDocumentBytes = 10 * 1024 * 1024;
const maxArtifactBytes = 20 * 1024 * 1024;

/// Revision of the text shown before a file is sent to CraftAI.
const documentConsentRevision = 'files-2026-10-v1-ru';

const docxMimeType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

enum DocumentSkill {
  quiz('quiz'),
  lessonPlan('lesson-plan');

  const DocumentSkill(this.wire);
  final String wire;

  static DocumentSkill parse(Object? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => throw FormatException('Unknown skill: $value'),
  );
}

enum DocumentFormat {
  docx('docx', docxMimeType),
  pdf('pdf', 'application/pdf');

  const DocumentFormat(this.wire, this.mimeType);
  final String wire;
  final String mimeType;

  static DocumentFormat parse(Object? value) => values.firstWhere(
    (f) => f.wire == value,
    orElse: () => throw FormatException('Unknown format: $value'),
  );
}

enum DocumentJobStatus {
  queued,
  parsing,
  generating,
  assembling,
  succeeded,
  failed,
  canceled,
  expired;

  bool get isFinal => switch (this) {
    succeeded || failed || canceled || expired => true,
    _ => false,
  };

  static DocumentJobStatus parse(Object? value) => values.firstWhere(
    (s) => s.name == value,
    orElse: () => throw FormatException('Unknown job status: $value'),
  );
}

final _uuid = RegExp(r'^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');
final _sha256 = RegExp(r'^[0-9a-f]{64}$');

String _uuidOf(Object? value, String name) {
  if (value is String && _uuid.hasMatch(value)) return value;
  throw FormatException('$name is not a UUID');
}

String _textOf(Object? value, String name, {int max = 1000}) {
  if (value is String && value.isNotEmpty && value.length <= max) return value;
  throw FormatException('$name is not valid text');
}

String _utcOf(Object? value, String name) {
  if (value is String && value.endsWith('Z') && DateTime.tryParse(value) != null) {
    return value;
  }
  throw FormatException('$name is not a UTC time');
}

class DocumentAttachment {
  const DocumentAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.uploaded,
    this.rejectReason,
    required this.createdAtUtc,
    required this.expiresAtUtc,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  /// False when the server refused the content (`status: rejected`).
  final bool uploaded;
  final String? rejectReason;
  final String createdAtUtc;
  final String expiresAtUtc;

  factory DocumentAttachment.fromJson(Map<String, dynamic> json) {
    final size = json['sizeBytes'];
    if (size is! int || size < 0 || size > maxDocumentBytes) {
      throw const FormatException('sizeBytes out of range');
    }
    final status = json['status'];
    if (status != 'uploaded' && status != 'rejected') {
      throw FormatException('Unknown attachment status: $status');
    }
    final mime = json['mimeType'];
    if (mime is! String || mime.isEmpty) {
      throw const FormatException('mimeType missing');
    }
    return DocumentAttachment(
      id: _uuidOf(json['id'], 'id'),
      fileName: _textOf(json['fileName'], 'fileName', max: 255),
      mimeType: mime,
      sizeBytes: size,
      uploaded: status == 'uploaded',
      rejectReason: json['rejectReason'] as String?,
      createdAtUtc: _utcOf(json['createdAtUtc'], 'createdAtUtc'),
      expiresAtUtc: _utcOf(json['expiresAtUtc'], 'expiresAtUtc'),
    );
  }
}

class DocumentArtifact {
  const DocumentArtifact({
    required this.id,
    required this.jobId,
    required this.format,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.expiresAtUtc,
  });

  final String id;
  final String jobId;
  final DocumentFormat format;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final String expiresAtUtc;

  factory DocumentArtifact.fromJson(Map<String, dynamic> json) {
    final format = DocumentFormat.parse(json['format']);
    if (json['mimeType'] != format.mimeType) {
      throw const FormatException('mimeType does not match format');
    }
    final size = json['sizeBytes'];
    if (size is! int || size < 1 || size > maxArtifactBytes) {
      throw const FormatException('sizeBytes out of range');
    }
    final hash = json['sha256'];
    if (hash is! String || !_sha256.hasMatch(hash)) {
      throw const FormatException('sha256 is not a hash');
    }
    return DocumentArtifact(
      id: _uuidOf(json['id'], 'id'),
      jobId: _uuidOf(json['jobId'], 'jobId'),
      format: format,
      fileName: _textOf(json['fileName'], 'fileName', max: 255),
      sizeBytes: size,
      sha256: hash,
      expiresAtUtc: _utcOf(json['expiresAtUtc'], 'expiresAtUtc'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'jobId': jobId,
    'format': format.wire,
    'fileName': fileName,
    'mimeType': format.mimeType,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'expiresAtUtc': expiresAtUtc,
  };
}

class DocumentJobError {
  const DocumentJobError({
    required this.code,
    required this.message,
    required this.retryable,
  });
  final String code;
  final String message;
  final bool retryable;

  factory DocumentJobError.fromJson(Map<String, dynamic> json) {
    final retryable = json['retryable'];
    if (retryable is! bool) throw const FormatException('retryable missing');
    return DocumentJobError(
      code: _textOf(json['code'], 'error.code', max: 100),
      message: _textOf(json['message'], 'error.message'),
      retryable: retryable,
    );
  }
}

class DocumentJob {
  const DocumentJob({
    required this.id,
    required this.attachmentId,
    required this.skill,
    required this.status,
    this.progress,
    this.artifacts = const [],
    this.error,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.expiresAtUtc,
  });

  final String id;
  final String attachmentId;
  final DocumentSkill skill;
  final DocumentJobStatus status;
  final int? progress;
  final List<DocumentArtifact> artifacts;
  final DocumentJobError? error;
  final String createdAtUtc;
  final String updatedAtUtc;
  final String expiresAtUtc;

  factory DocumentJob.fromJson(Map<String, dynamic> json) {
    final progress = json['progress'];
    if (progress != null && (progress is! int || progress < 0 || progress > 100)) {
      throw const FormatException('progress out of range');
    }
    final artifacts = json['artifacts'];
    if (artifacts is! List || artifacts.length > 2) {
      throw const FormatException('artifacts invalid');
    }
    return DocumentJob(
      id: _uuidOf(json['id'], 'id'),
      attachmentId: _uuidOf(json['attachmentId'], 'attachmentId'),
      skill: DocumentSkill.parse(json['skill']),
      status: DocumentJobStatus.parse(json['status']),
      progress: progress as int?,
      artifacts: [
        for (final a in artifacts)
          DocumentArtifact.fromJson(Map<String, dynamic>.from(a as Map)),
      ],
      error: json['error'] == null
          ? null
          : DocumentJobError.fromJson(
              Map<String, dynamic>.from(json['error'] as Map),
            ),
      createdAtUtc: _utcOf(json['createdAtUtc'], 'createdAtUtc'),
      updatedAtUtc: _utcOf(json['updatedAtUtc'], 'updatedAtUtc'),
      expiresAtUtc: _utcOf(json['expiresAtUtc'], 'expiresAtUtc'),
    );
  }
}

/// User-chosen settings of one document task; validated against the contract.
class DocumentParameters {
  const DocumentParameters({
    required this.language,
    this.topic,
    this.grade,
    this.itemsCount,
  });

  /// `ru` or `kk`.
  final String language;
  final String? topic;
  final int? grade;
  final int? itemsCount;

  /// Returns the first violated rule, or null when the values fit the contract.
  String? validate() {
    if (language != 'ru' && language != 'kk') return 'language';
    final topic = this.topic;
    if (topic != null && (topic.trim().isEmpty || topic.length > 200)) return 'topic';
    if (grade != null && (grade! < 1 || grade! > 11)) return 'grade';
    if (itemsCount != null && (itemsCount! < 1 || itemsCount! > 30)) return 'itemsCount';
    return null;
  }

  Map<String, dynamic> toJson() => {
    'language': language,
    if (topic != null && topic!.trim().isNotEmpty) 'topic': topic!.trim(),
    if (grade != null) 'grade': grade,
    if (itemsCount != null) 'itemsCount': itemsCount,
  };

  factory DocumentParameters.fromJson(Map<String, dynamic> json) =>
      DocumentParameters(
        language: json['language'] as String,
        topic: json['topic'] as String?,
        grade: json['grade'] as int?,
        itemsCount: json['itemsCount'] as int?,
      );
}

/// Body of `POST /builder/document-jobs`.
Map<String, dynamic> createDocumentJobBody({
  required String attachmentId,
  required DocumentSkill skill,
  required DocumentParameters parameters,
  required List<DocumentFormat> outputs,
}) {
  if (outputs.isEmpty || outputs.toSet().length != outputs.length) {
    throw ArgumentError('outputs must be a non-empty set');
  }
  final problem = parameters.validate();
  if (problem != null) throw ArgumentError('invalid parameter: $problem');
  return {
    'attachmentId': attachmentId,
    'skill': skill.wire,
    'parameters': parameters.toJson(),
    'outputs': [for (final o in outputs) o.wire],
  };
}

/// Client-side pre-check; the server validates the real content again.
enum SourceFileProblem { unsupportedType, empty, tooLarge }

({String mimeType})? sourceMimeForName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (name.substring(dot + 1).toLowerCase()) {
    'txt' => (mimeType: 'text/plain'),
    'docx' => (mimeType: docxMimeType),
    'pdf' => (mimeType: 'application/pdf'),
    _ => null,
  };
}

SourceFileProblem? checkSourceFile(String name, int sizeBytes) {
  if (sourceMimeForName(name) == null) return SourceFileProblem.unsupportedType;
  if (sizeBytes <= 0) return SourceFileProblem.empty;
  if (sizeBytes > maxDocumentBytes) return SourceFileProblem.tooLarge;
  return null;
}

/// The name without directories or control characters, at most 255 chars.
String safeSourceFileName(String name) {
  final base = name.split(RegExp(r'[\\/]')).last;
  final cleaned = String.fromCharCodes(
    base.runes.where((c) => c >= 0x20 && c != 0x7F),
  ).trim();
  if (cleaned.isEmpty) return 'document';
  if (cleaned.length <= 255) return cleaned;
  final dot = cleaned.lastIndexOf('.');
  final ext = dot >= 0 && cleaned.length - dot <= 10 ? cleaned.substring(dot) : '';
  return cleaned.substring(0, 255 - ext.length) + ext;
}
