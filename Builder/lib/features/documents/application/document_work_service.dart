import '../../models/infrastructure/craft_ai_client.dart';
import '../domain/document_models.dart';
import '../domain/document_problem.dart';
import '../domain/document_work.dart';
import '../infrastructure/builder_files_client.dart';
import '../infrastructure/document_work_repository.dart';

/// The request cannot start; nothing was stored or sent.
class DocumentStartException implements Exception {
  const DocumentStartException(this.problem);
  final DocumentProblem problem;
  @override
  String toString() => 'DocumentStartException(${problem.code})';
}

/// Drives a document task through upload, job creation and polling. Every
/// remote step reuses the keys fixed at creation, so repeating a step after a
/// lost answer never creates a second attachment or job. Network trouble keeps
/// the task and marks it `waiting`; only a definite server answer ends it.
class DocumentWorkService {
  DocumentWorkService({
    required this.client,
    required this.repository,
    required this.staging,
  });

  final BuilderFilesClient? client;
  final DocumentWorkRepository repository;
  final DocumentStagingStore staging;

  Future<DocumentWork> begin({
    required String ownerId,
    required String fileName,
    required List<int> bytes,
    required DocumentSkill skill,
    required DocumentParameters parameters,
    required List<DocumentFormat> outputs,
    required String consentRevision,
  }) async {
    final name = safeSourceFileName(fileName);
    final problem = checkSourceFile(name, bytes.length);
    if (problem != null) {
      throw DocumentStartException(switch (problem) {
        SourceFileProblem.unsupportedType => DocumentProblem.unsupportedType,
        SourceFileProblem.tooLarge => DocumentProblem.tooLarge,
        SourceFileProblem.empty => DocumentProblem.corrupt,
      });
    }
    // Throws ArgumentError for a malformed request before anything is stored.
    createDocumentJobBody(
      attachmentId: CraftAiClient.generateRequestId(),
      skill: skill,
      parameters: parameters,
      outputs: outputs,
    );
    final id = CraftAiClient.generateRequestId();
    final path = await staging.write(ownerId, id, name, bytes);
    final now = DateTime.now().toUtc().toIso8601String();
    final work = DocumentWork(
      id: id,
      fileName: name,
      sizeBytes: bytes.length,
      skill: skill,
      parameters: parameters,
      outputs: outputs,
      consentRevision: consentRevision,
      uploadKey: CraftAiClient.generateRequestId(),
      jobKey: CraftAiClient.generateRequestId(),
      stagedPath: path,
      createdAtUtc: now,
      updatedAtUtc: now,
    );
    await repository.save(ownerId, work);
    return work;
  }

  Future<DocumentWork> _save(String ownerId, DocumentWork work) async {
    await repository.save(ownerId, work);
    return work;
  }

  /// Ends the task with a definite problem and drops the staged copy.
  Future<DocumentWork> _fail(
    String ownerId,
    DocumentWork work,
    DocumentProblem problem, {
    DocumentStage stage = DocumentStage.failed,
  }) async {
    await staging.delete(ownerId, work.id);
    return _save(
      ownerId,
      work.copyWith(
        stage: stage,
        problemCode: problem.code,
        waiting: false,
        clearStagedPath: true,
      ),
    );
  }

  /// A failure that may disappear on its own: keep the task and try again.
  Future<DocumentWork> _wait(
    String ownerId,
    DocumentWork work,
    DocumentProblem problem,
  ) => _save(ownerId, work.copyWith(waiting: true, problemCode: problem.code));

  /// Whether [error] ends the task; null means "try again later".
  DocumentProblem? _definite(Object error) {
    if (error is CraftAiNetworkException || error is CraftAiCancelledException) {
      return null;
    }
    if (error is CraftAiAuthException || error is CraftAiForbiddenException) {
      return null;
    }
    if (error is CraftAiException) {
      final status = error.statusCode ?? 0;
      final known = DocumentProblem.fromCode(error.code);
      if (known != DocumentProblem.unknown) {
        // A busy or failing service may recover; refusals about the file may not.
        return known == DocumentProblem.unavailable ? null : known;
      }
      if (status == 404 || status == 410) return DocumentProblem.expired;
      if (status == 413) return DocumentProblem.tooLarge;
      if (status == 415) return DocumentProblem.unsupportedType;
      if (status == 429) return DocumentProblem.limitReached;
      if (status >= 500) return null;
      return DocumentProblem.unknown;
    }
    // A response that breaks the contract is not retried blindly.
    if (error is FormatException) return DocumentProblem.unknown;
    return null;
  }

  DocumentProblem _transient(Object error) {
    if (error is CraftAiAuthException || error is CraftAiForbiddenException) {
      return DocumentProblem.auth;
    }
    if (error is CraftAiNetworkException) return DocumentProblem.noNetwork;
    return DocumentProblem.unavailable;
  }

  Future<DocumentWork> _onError(
    String ownerId,
    DocumentWork work,
    Object error,
  ) async {
    final definite = _definite(error);
    return definite == null
        ? _wait(ownerId, work, _transient(error))
        : _fail(ownerId, work, definite);
  }

  /// Performs the next step of the task; safe to call repeatedly.
  Future<DocumentWork?> advance(String ownerId, String id) async {
    var work = await repository.get(ownerId, id);
    if (work == null || !work.isActive) return work;
    final api = client;
    if (api == null) return _wait(ownerId, work, DocumentProblem.auth);

    try {
      switch (work.stage) {
        case DocumentStage.staged:
          return await _upload(ownerId, work, api);
        case DocumentStage.uploaded:
          return await _submit(ownerId, work, api);
        case DocumentStage.submitted:
          return await _poll(ownerId, work, api);
        default:
          return work;
      }
    } catch (error) {
      work = await repository.get(ownerId, id) ?? work;
      return _onError(ownerId, work, error);
    }
  }

  Future<DocumentWork> _upload(
    String ownerId,
    DocumentWork work,
    BuilderFilesClient api,
  ) async {
    if (work.cancelRequested) {
      return _fail(ownerId, work, DocumentProblem.unknown, stage: DocumentStage.canceled);
    }
    final path = work.stagedPath;
    final bytes = path == null ? null : await staging.read(path);
    if (bytes == null) return _fail(ownerId, work, DocumentProblem.unknown);

    final attachment = await api.upload(
      fileName: work.fileName,
      bytes: bytes,
      idempotencyKey: work.uploadKey,
      consentRevision: work.consentRevision,
    );
    if (!attachment.uploaded) {
      return _fail(ownerId, work, DocumentProblem.fromCode(attachment.rejectReason));
    }
    // The server owns the file now; the client copy is no longer needed.
    await staging.delete(ownerId, work.id);
    return _save(
      ownerId,
      work.copyWith(
        stage: DocumentStage.uploaded,
        attachmentId: attachment.id,
        waiting: false,
        clearStagedPath: true,
      ),
    );
  }

  Future<DocumentWork> _submit(
    String ownerId,
    DocumentWork work,
    BuilderFilesClient api,
  ) async {
    if (work.cancelRequested) {
      await _bestEffort(() => api.deleteAttachment(work.attachmentId!));
      return _fail(ownerId, work, DocumentProblem.unknown, stage: DocumentStage.canceled);
    }
    final job = await api.createJob(
      attachmentId: work.attachmentId!,
      skill: work.skill,
      parameters: work.parameters,
      outputs: work.outputs,
      idempotencyKey: work.jobKey,
    );
    return _applyJob(ownerId, work.copyWith(jobId: job.id, stage: DocumentStage.submitted), job);
  }

  Future<DocumentWork> _poll(
    String ownerId,
    DocumentWork work,
    BuilderFilesClient api,
  ) async {
    if (work.cancelRequested) await api.cancelJob(work.jobId!);
    final job = await api.job(work.jobId!);
    return _applyJob(ownerId, work, job);
  }

  Future<DocumentWork> _applyJob(
    String ownerId,
    DocumentWork work,
    DocumentJob job,
  ) {
    final base = work.copyWith(
      remoteStatus: job.status,
      progress: job.progress,
      waiting: false,
    );
    switch (job.status) {
      case DocumentJobStatus.succeeded:
        // Only a job with complete artifacts is a result.
        if (job.artifacts.isEmpty) return _fail(ownerId, base, DocumentProblem.unknown);
        return _save(
          ownerId,
          base.copyWith(stage: DocumentStage.succeeded, artifacts: job.artifacts, progress: 100),
        );
      case DocumentJobStatus.failed:
        return _fail(ownerId, base, DocumentProblem.fromCode(job.error?.code));
      case DocumentJobStatus.canceled:
        return _fail(ownerId, base, DocumentProblem.unknown, stage: DocumentStage.canceled);
      case DocumentJobStatus.expired:
        return _fail(ownerId, base, DocumentProblem.expired, stage: DocumentStage.expired);
      default:
        return _save(ownerId, base);
    }
  }

  Future<void> _bestEffort(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  /// Asks to stop. Before upload completes this is local; with a job it is the
  /// server's idempotent cancel, and the task ends when the server confirms.
  Future<DocumentWork?> requestCancel(String ownerId, String id) async {
    final work = await repository.get(ownerId, id);
    if (work == null || !work.isActive) return work;
    final marked = await _save(ownerId, work.copyWith(cancelRequested: true));
    return advance(ownerId, marked.id);
  }

  /// Tries a waiting task again now. A finished task cannot be resumed: the
  /// source file is gone from the device and the server, so it is started anew.
  Future<DocumentWork?> retryNow(String ownerId, String id) =>
      advance(ownerId, id);

  /// Deletes the task locally and, best effort, the job and attachment on the server.
  Future<void> remove(String ownerId, String id) async {
    final work = await repository.get(ownerId, id);
    if (work == null) return;
    await _deleteRemote(work);
    await staging.delete(ownerId, id);
    await repository.delete(ownerId, id);
  }

  Future<void> _deleteRemote(DocumentWork work) async {
    final api = client;
    if (api == null) return;
    if (work.jobId != null) {
      if (work.isActive) await _bestEffort(() => api.cancelJob(work.jobId!));
      await _bestEffort(() => api.deleteJob(work.jobId!));
    }
    if (work.attachmentId != null) {
      await _bestEffort(() => api.deleteAttachment(work.attachmentId!));
    }
  }

  /// Sign-out or owner change: stop server work, delete remote copies when
  /// reachable, and leave no staged file or task behind.
  Future<void> clearOwner(String ownerId) async {
    for (final work in await repository.list(ownerId)) {
      await _deleteRemote(work);
      await repository.delete(ownerId, work.id);
    }
    await staging.deleteOwner(ownerId);
  }
}
