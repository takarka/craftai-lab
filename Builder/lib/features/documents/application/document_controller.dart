import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/storage_providers.dart';
import '../../models/model_providers.dart';
import '../domain/document_models.dart';
import '../domain/document_work.dart';
import '../infrastructure/artifact_file_store.dart';
import '../infrastructure/builder_files_client.dart';
import '../infrastructure/document_work_repository.dart';
import 'document_work_service.dart';

final builderFilesClientProvider = Provider<BuilderFilesClient?>((ref) {
  final api = ref.watch(craftAiClientProvider);
  return api == null ? null : BuilderFilesClient(api);
});

final documentWorkRepositoryProvider = Provider<DocumentWorkRepository>((ref) {
  final db = ref.watch(storageDatabaseProvider);
  if (db == null) return InMemoryDocumentWorkRepository();
  return PersistentDocumentWorkRepository(database: db);
});

final documentStagingStoreProvider = Provider<DocumentStagingStore>((ref) {
  if (kIsWeb) return InMemoryDocumentStagingStore();
  return FileDocumentStagingStore(() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'document_uploads'));
  });
});

/// Verified downloads of finished documents (private app storage).
final artifactFileStoreProvider = Provider<ArtifactFileStore>(
  (ref) => ArtifactFileStore(() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'artifact_downloads'));
  }),
);

final documentWorkServiceProvider = Provider<DocumentWorkService>(
  (ref) => DocumentWorkService(
    client: ref.watch(builderFilesClientProvider),
    repository: ref.watch(documentWorkRepositoryProvider),
    staging: ref.watch(documentStagingStoreProvider),
  ),
);

/// Pause between polling rounds; tests shorten it.
final documentPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);

/// A file the user chose; its bytes are read only when the task starts.
class PickedDocument {
  const PickedDocument({
    required this.name,
    required this.sizeBytes,
    required this.readBytes,
  });
  final String name;
  final int sizeBytes;
  final Future<List<int>> Function() readBytes;
}

abstract class DocumentPicker {
  Future<PickedDocument?> pick();
}

/// Native system picker limited to TXT, DOCX and PDF.
class SystemDocumentPicker implements DocumentPicker {
  const SystemDocumentPicker();

  @override
  Future<PickedDocument?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'docx', 'pdf'],
    );
    if (file == null) return null;
    return PickedDocument(
      name: file.name,
      sizeBytes: await file.length() ?? 0,
      readBytes: file.readAsBytes,
    );
  }
}

final documentPickerProvider = Provider<DocumentPicker>(
  (ref) => const SystemDocumentPicker(),
);

class DocumentsState {
  const DocumentsState({this.items = const [], this.loaded = false});
  final List<DocumentWork> items;
  final bool loaded;
}

final documentControllerProvider = NotifierProvider.autoDispose
    .family<DocumentController, DocumentsState, String>(
      (ownerId) => DocumentController(ownerId),
    );

class DocumentController extends Notifier<DocumentsState> {
  DocumentController(this.ownerId);
  final String ownerId;
  bool _disposed = false;
  bool _looping = false;
  final _inFlight = <String>{};

  DocumentWorkService get _service => ref.read(documentWorkServiceProvider);

  @override
  DocumentsState build() {
    ref.onDispose(() => _disposed = true);
    Future.microtask(load);
    return const DocumentsState();
  }

  Future<void> _refresh() async {
    if (_disposed) return;
    final items = await ref.read(documentWorkRepositoryProvider).list(ownerId);
    if (!_disposed) state = DocumentsState(items: items, loaded: true);
  }

  /// Shows stored tasks and resumes the ones that were still running.
  Future<void> load() async {
    await _refresh();
    // Copies of deleted or expired documents and interrupted downloads go now.
    try {
      await ref.read(artifactFileStoreProvider).sweep(ownerId, {
        for (final work in state.items)
          for (final artifact in work.artifacts) artifact.id,
      });
    } catch (_) {}
    _poll();
  }

  Future<DocumentWork> start({
    required PickedDocument file,
    required DocumentSkill skill,
    required DocumentParameters parameters,
    required List<DocumentFormat> outputs,
  }) async {
    // Throws DocumentStartException/ArgumentError before anything is stored.
    final work = await _service.begin(
      ownerId: ownerId,
      fileName: file.name,
      bytes: await file.readBytes(),
      skill: skill,
      parameters: parameters,
      outputs: outputs,
      consentRevision: documentConsentRevision,
    );
    await _refresh();
    _poll();
    return work;
  }

  Future<void> cancel(String id) async {
    await _service.requestCancel(ownerId, id);
    await _refresh();
    _poll();
  }

  Future<void> retryNow(String id) async {
    await _service.retryNow(ownerId, id);
    await _refresh();
    _poll();
  }

  Future<void> remove(String id) async {
    final artifacts = state.items
        .where((w) => w.id == id)
        .expand((w) => w.artifacts)
        .toList();
    final store = ref.read(artifactFileStoreProvider);
    await _service.remove(ownerId, id);
    for (final artifact in artifacts) {
      try {
        await store.delete(ownerId, artifact.id);
      } catch (_) {}
    }
    await _refresh();
  }

  /// One round per interval until nothing is active, or the connection keeps
  /// failing. The user can resume with "try now" or by reopening the screen.
  void _poll() {
    if (_looping || _disposed) return;
    _looping = true;
    final service = _service;
    final base = ref.read(documentPollIntervalProvider);
    unawaited(() async {
      var waitingRounds = 0;
      try {
        while (!_disposed) {
          final active = state.items.where((w) => w.isActive).toList();
          if (active.isEmpty) break;
          for (final work in active) {
            if (_disposed || !_inFlight.add(work.id)) continue;
            try {
              await service.advance(ownerId, work.id);
            } finally {
              _inFlight.remove(work.id);
            }
          }
          await _refresh();
          final stillActive = state.items.where((w) => w.isActive);
          if (stillActive.isEmpty) break;
          waitingRounds = stillActive.every((w) => w.waiting) ? waitingRounds + 1 : 0;
          if (waitingRounds >= 6 || _disposed) break;
          await Future<void>.delayed(base * (1 << waitingRounds.clamp(0, 4)));
        }
      } finally {
        _looping = false;
      }
    }());
  }
}

/// Sign-out and account deletion: stops polling, deletes the owner's server
/// jobs/attachments while the session still authorizes it (bounded wait,
/// failures are ignored) and removes every staged file and local task.
Future<void> clearDocumentWork(WidgetRef ref, String ownerId) async {
  final service = ref.read(documentWorkServiceProvider);
  final files = ref.read(artifactFileStoreProvider);
  for (final step in <Future<void> Function()>[
    () => service.clearOwner(ownerId),
    () => files.deleteOwner(ownerId),
  ]) {
    try {
      await step().timeout(const Duration(seconds: 8));
    } catch (_) {
      // Whatever stayed on the server expires by its own TTL.
    }
  }
  ref.invalidate(documentControllerProvider(ownerId));
}
