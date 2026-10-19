import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../models/infrastructure/craft_ai_client.dart';
import '../domain/document_models.dart';
import '../domain/document_problem.dart';
import '../infrastructure/artifact_file_store.dart';
import '../infrastructure/builder_files_client.dart';

/// The download did not produce a verified file.
class ArtifactDownloadException implements Exception {
  const ArtifactDownloadException(this.problem);
  final DocumentProblem problem;
  @override
  String toString() => 'ArtifactDownloadException(${problem.code})';
}

/// The user stopped the download; nothing is kept.
class ArtifactDownloadCancelled implements Exception {
  const ArtifactDownloadCancelled();
}

/// Downloads a server artifact into private storage. A file gets its final
/// name only when its size, SHA-256 and format signature match the server's
/// metadata, so a partial file or an error page is never presented as a document.
class ArtifactDownloadService {
  ArtifactDownloadService({
    required this.client,
    required this.store,
    DateTime Function()? now,
    IOSink Function(File part, FileMode mode)? openSink,
  }) : _now = now ?? DateTime.now,
       _openSink = openSink ?? ((part, mode) => part.openWrite(mode: mode));

  final BuilderFilesClient? client;
  final ArtifactFileStore store;
  final DateTime Function() _now;
  final IOSink Function(File part, FileMode mode) _openSink;

  static bool _isNoSpace(FileSystemException error) {
    final code = error.osError?.errorCode;
    return code == 28 /* ENOSPC */ ||
        code == 112 /* ERROR_DISK_FULL */ ||
        code == 39 /* ERROR_HANDLE_DISK_FULL */ ||
        (error.osError?.message ?? error.message).toLowerCase().contains('no space');
  }

  static bool _hasSignature(DocumentFormat format, List<int> head) {
    switch (format) {
      case DocumentFormat.pdf:
        return head.length >= 5 &&
            head[0] == 0x25 && head[1] == 0x50 && head[2] == 0x44 && head[3] == 0x46 && head[4] == 0x2D;
      case DocumentFormat.docx:
        // A DOCX is a ZIP container.
        return head.length >= 4 && head[0] == 0x50 && head[1] == 0x4B && head[2] == 0x03 && head[3] == 0x04;
    }
  }

  Future<bool> _verified(File file, DocumentArtifact artifact) async {
    if (!await file.exists() || await file.length() != artifact.sizeBytes) return false;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == artifact.sha256;
  }

  DocumentProblem _problemFor(Object error) {
    if (error is CraftAiException) {
      if (error is CraftAiNetworkException) return DocumentProblem.noNetwork;
      if (error is CraftAiAuthException || error is CraftAiForbiddenException) {
        return DocumentProblem.auth;
      }
      final status = error.statusCode ?? 0;
      if (status == 410 || error.code == 'artifact.expired') {
        return DocumentProblem.artifactExpired;
      }
      if (status == 404) return DocumentProblem.expired;
      if (status >= 500) return DocumentProblem.unavailable;
      return DocumentProblem.unknown;
    }
    return DocumentProblem.unknown;
  }

  /// Returns the verified local file for [listed], downloading it if needed.
  /// [onProgress] reports bytes stored so far and the expected total.
  Future<File> ensureDownloaded(
    String ownerId,
    DocumentArtifact listed, {
    void Function(int received, int total)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    final ready = await store.readyFile(ownerId, listed);
    if (await _verified(ready, listed)) return ready;

    if (!DateTime.parse(listed.expiresAtUtc).isAfter(_now().toUtc())) {
      await store.delete(ownerId, listed.id);
      throw const ArtifactDownloadException(DocumentProblem.artifactExpired);
    }
    final api = client;
    if (api == null) throw const ArtifactDownloadException(DocumentProblem.auth);

    try {
      final meta = await api.artifact(listed.id);
      // The listing and the artifact resource must describe the same file.
      if (meta.id != listed.id ||
          meta.jobId != listed.jobId ||
          meta.format != listed.format ||
          meta.sizeBytes != listed.sizeBytes ||
          meta.sha256 != listed.sha256) {
        await store.delete(ownerId, listed.id);
        throw const ArtifactDownloadException(DocumentProblem.integrity);
      }
      if (!DateTime.parse(meta.expiresAtUtc).isAfter(_now().toUtc())) {
        await store.delete(ownerId, listed.id);
        throw const ArtifactDownloadException(DocumentProblem.artifactExpired);
      }
      return await _fetch(ownerId, meta, api, onProgress, abortTrigger);
    } on ArtifactDownloadException {
      rethrow;
    } on ArtifactDownloadCancelled {
      rethrow;
    } on CraftAiCancelledException {
      await store.delete(ownerId, listed.id);
      throw const ArtifactDownloadCancelled();
    } on FormatException {
      throw const ArtifactDownloadException(DocumentProblem.unknown);
    } catch (error) {
      throw ArtifactDownloadException(_problemFor(error));
    }
  }

  Future<File> _fetch(
    String ownerId,
    DocumentArtifact artifact,
    BuilderFilesClient api,
    void Function(int received, int total)? onProgress,
    Future<void>? abortTrigger,
  ) async {
    final part = await store.partFile(ownerId, artifact.id);
    var have = await part.exists() ? await part.length() : 0;
    if (have >= artifact.sizeBytes) {
      await part.delete();
      have = 0;
    }

    IOSink? sink;
    var received = have;
    var overflow = false;
    try {
      await api.downloadArtifact(
        artifact.id,
        rangeStart: have,
        abortTrigger: abortTrigger,
        onResponse: (head) async {
          // 206 continues the stored bytes; 200 means the server restarted.
          final append = head.resumed && have > 0;
          if (!append) received = 0;
          sink = _openSink(part, append ? FileMode.append : FileMode.write);
          onProgress?.call(received, artifact.sizeBytes);
        },
        onChunk: (chunk) async {
          sink!.add(chunk);
          // Writes fail asynchronously (e.g. a full disk); surface that now.
          await sink!.flush();
          received += chunk.length;
          if (received > artifact.sizeBytes) overflow = true;
          onProgress?.call(received, artifact.sizeBytes);
        },
      );
      await sink?.flush();
      await sink?.close();
      sink = null;
    } on FileSystemException catch (error) {
      await _discard(sink);
      await store.delete(ownerId, artifact.id);
      throw ArtifactDownloadException(
        _isNoSpace(error) ? DocumentProblem.noSpace : DocumentProblem.unknown,
      );
    } on CraftAiCancelledException {
      await _discard(sink);
      await store.delete(ownerId, artifact.id);
      rethrow;
    } catch (_) {
      // Network trouble keeps the partial bytes so the next try can resume.
      await _discard(sink);
      rethrow;
    }

    if (overflow) {
      await store.delete(ownerId, artifact.id);
      throw const ArtifactDownloadException(DocumentProblem.integrity);
    }
    if (await part.length() < artifact.sizeBytes) {
      // The connection ended early: keep the bytes, but this is not a document.
      throw const CraftAiNetworkException('Download ended before the full file.');
    }
    final head = await part.openRead(0, 8).expand((b) => b).toList();
    final digest = await sha256.bind(part.openRead()).first;
    if (await part.length() != artifact.sizeBytes ||
        digest.toString() != artifact.sha256 ||
        !_hasSignature(artifact.format, head)) {
      await store.delete(ownerId, artifact.id);
      throw const ArtifactDownloadException(DocumentProblem.integrity);
    }
    final ready = await store.readyFile(ownerId, artifact);
    if (await ready.exists()) await ready.delete();
    return part.rename(ready.path);
  }

  Future<void> _discard(IOSink? sink) async {
    try {
      await sink?.close();
    } catch (_) {}
  }
}
