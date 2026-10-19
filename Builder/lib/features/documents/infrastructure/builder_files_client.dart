import '../../models/infrastructure/craft_ai_client.dart';
import '../domain/document_models.dart';

/// Typed access to the attachment and document-job endpoints. Artifact
/// download is a separate step (EF-05).
class BuilderFilesClient {
  const BuilderFilesClient(this.api);
  final CraftAiClient api;
  static const _root = '/builder';

  static const _uploadTimeout = Duration(seconds: 90);

  /// [idempotencyKey] is reused when an upload with an unknown outcome is
  /// repeated, so the server returns the same attachment instead of a second one.
  Future<DocumentAttachment> upload({
    required String fileName,
    required List<int> bytes,
    required String idempotencyKey,
    required String consentRevision,
  }) async {
    final mime = sourceMimeForName(fileName);
    if (mime == null) throw ArgumentError('Unsupported file type.');
    return DocumentAttachment.fromJson(
      await api.requestJson(
        'POST',
        '$_root/attachments',
        headers: {'Idempotency-Key': idempotencyKey},
        fields: {'consentRevision': consentRevision},
        upload: UploadFile(
          field: 'file',
          fileName: fileName,
          bytes: bytes,
          contentType: mime.mimeType,
        ),
        timeout: _uploadTimeout,
      ),
    );
  }

  Future<DocumentAttachment> attachment(String id) async =>
      DocumentAttachment.fromJson(
        await api.getJson('$_root/attachments/${Uri.encodeComponent(id)}'),
      );

  Future<void> deleteAttachment(String id) async {
    await api.requestJson(
      'DELETE',
      '$_root/attachments/${Uri.encodeComponent(id)}',
    );
  }

  Future<DocumentJob> createJob({
    required String attachmentId,
    required DocumentSkill skill,
    required DocumentParameters parameters,
    required List<DocumentFormat> outputs,
    required String idempotencyKey,
  }) async => DocumentJob.fromJson(
    await api.requestJson(
      'POST',
      '$_root/document-jobs',
      body: createDocumentJobBody(
        attachmentId: attachmentId,
        skill: skill,
        parameters: parameters,
        outputs: outputs,
      ),
      headers: {'Idempotency-Key': idempotencyKey},
    ),
  );

  Future<DocumentJob> job(String id) async => DocumentJob.fromJson(
    await api.getJson('$_root/document-jobs/${Uri.encodeComponent(id)}'),
  );

  /// Idempotent. The returned job may already be `succeeded`; read its status.
  Future<void> cancelJob(String id) async {
    await api.requestJson(
      'POST',
      '$_root/document-jobs/${Uri.encodeComponent(id)}/cancel',
    );
  }

  Future<void> deleteJob(String id) async {
    await api.requestJson(
      'DELETE',
      '$_root/document-jobs/${Uri.encodeComponent(id)}',
    );
  }

  Future<DocumentArtifact> artifact(String id) async => DocumentArtifact.fromJson(
    await api.getJson('$_root/artifacts/${Uri.encodeComponent(id)}'),
  );

  /// Streams the artifact bytes; [rangeStart] resumes a partial download.
  Future<DownloadHead> downloadArtifact(
    String id, {
    required Future<void> Function(List<int> chunk) onChunk,
    Future<void> Function(DownloadHead head)? onResponse,
    int rangeStart = 0,
    Future<void>? abortTrigger,
  }) => api.download(
    '$_root/artifacts/${Uri.encodeComponent(id)}/content',
    onChunk: onChunk,
    onResponse: onResponse,
    rangeStart: rangeStart,
    abortTrigger: abortTrigger,
  );
}
