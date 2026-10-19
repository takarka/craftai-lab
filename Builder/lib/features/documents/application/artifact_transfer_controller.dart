import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/document_models.dart';
import '../domain/document_problem.dart';
import '../infrastructure/artifact_file_store.dart';
import 'artifact_download_service.dart';
import 'document_controller.dart';

final artifactDownloadServiceProvider = Provider<ArtifactDownloadService>(
  (ref) => ArtifactDownloadService(
    client: ref.watch(builderFilesClientProvider),
    store: ref.watch(artifactFileStoreProvider),
  ),
);

enum OpenOutcome { opened, noApp, failed }

/// Hands a verified file to the operating system; replaced in tests.
abstract class ArtifactActions {
  Future<OpenOutcome> open(File file, String mimeType);

  /// Lets the user choose where to store a copy; false if they cancelled.
  Future<bool> save(File file, String fileName, String mimeType);
  Future<void> share(File file, String fileName, String mimeType);
}

class SystemArtifactActions implements ArtifactActions {
  const SystemArtifactActions();

  @override
  Future<OpenOutcome> open(File file, String mimeType) async {
    final result = await OpenFilex.open(file.path, type: mimeType);
    return switch (result.type) {
      ResultType.done => OpenOutcome.opened,
      ResultType.noAppToOpen => OpenOutcome.noApp,
      _ => OpenOutcome.failed,
    };
  }

  @override
  Future<bool> save(File file, String fileName, String mimeType) async {
    final saved = await FilePicker.saveFile(
      fileName: fileName,
      bytes: await file.readAsBytes(),
      mimeType: mimeType,
    );
    return saved != null;
  }

  @override
  Future<void> share(File file, String fileName, String mimeType) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mimeType, name: fileName)]),
    );
  }
}

final artifactActionsProvider = Provider<ArtifactActions>(
  (ref) => const SystemArtifactActions(),
);

enum TransferPhase { downloading, ready, failed }

class ArtifactTransfer {
  const ArtifactTransfer({
    required this.phase,
    this.received = 0,
    this.total = 0,
    this.problem,
  });
  final TransferPhase phase;
  final int received;
  final int total;
  final DocumentProblem? problem;

  double? get fraction => total <= 0 ? null : (received / total).clamp(0, 1);
}

enum ArtifactAction { open, save, share }

/// What happened after the user chose an action on a document.
enum ArtifactResult {
  done,
  saved,
  cancelledByUser,
  noAppToOpen,
  failed,

  /// The download did not finish; see the transfer's problem.
  downloadFailed,
}

final artifactTransferProvider = NotifierProvider.autoDispose
    .family<ArtifactTransferController, Map<String, ArtifactTransfer>, String>(
      (ownerId) => ArtifactTransferController(ownerId),
    );

class ArtifactTransferController extends Notifier<Map<String, ArtifactTransfer>> {
  ArtifactTransferController(this.ownerId);
  final String ownerId;
  final _aborts = <String, Completer<void>>{};
  bool _disposed = false;

  @override
  Map<String, ArtifactTransfer> build() {
    ref.onDispose(() {
      _disposed = true;
      for (final abort in _aborts.values) {
        if (!abort.isCompleted) abort.complete();
      }
    });
    return const {};
  }

  void _set(String id, ArtifactTransfer transfer) {
    if (!_disposed) state = {...state, id: transfer};
  }

  /// Downloads (or reuses the verified copy of) [artifact].
  Future<File?> download(DocumentArtifact artifact) async {
    if (state[artifact.id]?.phase == TransferPhase.downloading) return null;
    final service = ref.read(artifactDownloadServiceProvider);
    final abort = Completer<void>();
    _aborts[artifact.id] = abort;
    _set(
      artifact.id,
      ArtifactTransfer(phase: TransferPhase.downloading, total: artifact.sizeBytes),
    );
    try {
      final file = await service.ensureDownloaded(
        ownerId,
        artifact,
        abortTrigger: abort.future,
        onProgress: (received, total) => _set(
          artifact.id,
          ArtifactTransfer(
            phase: TransferPhase.downloading,
            received: received,
            total: total,
          ),
        ),
      );
      _set(
        artifact.id,
        ArtifactTransfer(
          phase: TransferPhase.ready,
          received: artifact.sizeBytes,
          total: artifact.sizeBytes,
        ),
      );
      return file;
    } on ArtifactDownloadCancelled {
      if (!_disposed) state = {...state}..remove(artifact.id);
      return null;
    } on ArtifactDownloadException catch (error) {
      _set(artifact.id, ArtifactTransfer(phase: TransferPhase.failed, problem: error.problem));
      return null;
    } catch (_) {
      _set(artifact.id, const ArtifactTransfer(phase: TransferPhase.failed, problem: DocumentProblem.unknown));
      return null;
    } finally {
      _aborts.remove(artifact.id);
    }
  }

  void cancel(String artifactId) {
    final abort = _aborts[artifactId];
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  /// Downloads if needed, then opens, saves or shares the verified copy.
  Future<ArtifactResult> perform(DocumentArtifact artifact, ArtifactAction action) async {
    final file = await download(artifact);
    if (file == null) {
      return state[artifact.id]?.phase == TransferPhase.failed
          ? ArtifactResult.downloadFailed
          : ArtifactResult.cancelledByUser;
    }
    final actions = ref.read(artifactActionsProvider);
    final name = ArtifactFileStore.localName(artifact);
    try {
      switch (action) {
        case ArtifactAction.open:
          return switch (await actions.open(file, artifact.format.mimeType)) {
            OpenOutcome.opened => ArtifactResult.done,
            OpenOutcome.noApp => ArtifactResult.noAppToOpen,
            OpenOutcome.failed => ArtifactResult.failed,
          };
        case ArtifactAction.save:
          return await actions.save(file, name, artifact.format.mimeType)
              ? ArtifactResult.saved
              : ArtifactResult.cancelledByUser;
        case ArtifactAction.share:
          await actions.share(file, name, artifact.format.mimeType);
          return ArtifactResult.done;
      }
    } catch (_) {
      return ArtifactResult.failed;
    }
  }
}
