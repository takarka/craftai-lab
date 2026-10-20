import 'dart:convert';

import 'document_models.dart';

/// Local progress of one document task, persisted so it survives a lost
/// connection or an app restart.
enum DocumentStage {
  /// File copied to the app's staging area; not yet accepted by the server.
  staged,

  /// The server holds the attachment; the job is not created yet.
  uploaded,

  /// A job exists on the server (see [DocumentWork.remoteStatus]).
  submitted,
  succeeded,
  failed,
  canceled,
  expired;

  bool get isFinal => switch (this) {
    succeeded || failed || canceled || expired => true,
    _ => false,
  };
}

class DocumentWork {
  const DocumentWork({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.skill,
    required this.parameters,
    required this.outputs,
    required this.consentRevision,
    required this.uploadKey,
    required this.jobKey,
    this.stage = DocumentStage.staged,
    this.stagedPath,
    this.attachmentId,
    this.jobId,
    this.remoteStatus,
    this.progress,
    this.cancelRequested = false,
    this.waiting = false,
    this.problemCode,
    this.artifacts = const [],
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  final String id;
  final String fileName;
  final int sizeBytes;
  final DocumentSkill skill;
  final DocumentParameters parameters;
  final List<DocumentFormat> outputs;
  final String consentRevision;

  /// Idempotency keys fixed at creation: a repeat after a lost answer reuses them.
  final String uploadKey;
  final String jobKey;
  final DocumentStage stage;
  final String? stagedPath;
  final String? attachmentId;
  final String? jobId;
  final DocumentJobStatus? remoteStatus;
  final int? progress;
  final bool cancelRequested;

  /// The last attempt found no connection; the work continues when it returns.
  final bool waiting;
  final String? problemCode;
  final List<DocumentArtifact> artifacts;
  final String createdAtUtc;
  final String updatedAtUtc;

  bool get isActive => !stage.isFinal;

  DocumentWork copyWith({
    DocumentStage? stage,
    String? stagedPath,
    bool clearStagedPath = false,
    String? attachmentId,
    String? jobId,
    DocumentJobStatus? remoteStatus,
    int? progress,
    bool? cancelRequested,
    bool? waiting,
    String? problemCode,
    List<DocumentArtifact>? artifacts,
  }) => DocumentWork(
    id: id,
    fileName: fileName,
    sizeBytes: sizeBytes,
    skill: skill,
    parameters: parameters,
    outputs: outputs,
    consentRevision: consentRevision,
    uploadKey: uploadKey,
    jobKey: jobKey,
    stage: stage ?? this.stage,
    stagedPath: clearStagedPath ? null : stagedPath ?? this.stagedPath,
    attachmentId: attachmentId ?? this.attachmentId,
    jobId: jobId ?? this.jobId,
    remoteStatus: remoteStatus ?? this.remoteStatus,
    progress: progress ?? this.progress,
    cancelRequested: cancelRequested ?? this.cancelRequested,
    waiting: waiting ?? this.waiting,
    problemCode: problemCode ?? this.problemCode,
    artifacts: artifacts ?? this.artifacts,
    createdAtUtc: createdAtUtc,
    updatedAtUtc: DateTime.now().toUtc().toIso8601String(),
  );

  Map<String, Object?> toRow(String ownerId) => {
    'owner_id': ownerId,
    'id': id,
    'file_name': fileName,
    'size_bytes': sizeBytes,
    'skill': skill.wire,
    'params_json': jsonEncode(parameters.toJson()),
    'outputs_json': jsonEncode([for (final o in outputs) o.wire]),
    'consent_revision': consentRevision,
    'upload_key': uploadKey,
    'job_key': jobKey,
    'stage': stage.name,
    'staged_path': stagedPath,
    'attachment_id': attachmentId,
    'job_id': jobId,
    'remote_status': remoteStatus?.name,
    'progress': progress,
    'cancel_requested': cancelRequested ? 1 : 0,
    'waiting': waiting ? 1 : 0,
    'problem_code': problemCode,
    'artifacts_json': jsonEncode([for (final a in artifacts) a.toJson()]),
    'created_at_utc': createdAtUtc,
    'updated_at_utc': updatedAtUtc,
  };

  factory DocumentWork.fromRow(Map<String, Object?> row) => DocumentWork(
    id: row['id'] as String,
    fileName: row['file_name'] as String,
    sizeBytes: row['size_bytes'] as int,
    skill: DocumentSkill.parse(row['skill']),
    parameters: DocumentParameters.fromJson(
      Map<String, dynamic>.from(jsonDecode(row['params_json'] as String) as Map),
    ),
    outputs: [
      for (final o in jsonDecode(row['outputs_json'] as String) as List)
        DocumentFormat.parse(o),
    ],
    consentRevision: row['consent_revision'] as String,
    uploadKey: row['upload_key'] as String,
    jobKey: row['job_key'] as String,
    stage: DocumentStage.values.byName(row['stage'] as String),
    stagedPath: row['staged_path'] as String?,
    attachmentId: row['attachment_id'] as String?,
    jobId: row['job_id'] as String?,
    remoteStatus: row['remote_status'] == null
        ? null
        : DocumentJobStatus.parse(row['remote_status']),
    progress: row['progress'] as int?,
    cancelRequested: (row['cancel_requested'] as int) == 1,
    waiting: (row['waiting'] as int) == 1,
    problemCode: row['problem_code'] as String?,
    artifacts: [
      for (final a in jsonDecode(row['artifacts_json'] as String) as List)
        DocumentArtifact.fromJson(Map<String, dynamic>.from(a as Map)),
    ],
    createdAtUtc: row['created_at_utc'] as String,
    updatedAtUtc: row['updated_at_utc'] as String,
  );
}
