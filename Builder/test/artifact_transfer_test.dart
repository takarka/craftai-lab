import 'dart:io';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/features/documents/application/artifact_download_service.dart';
import 'package:builder/features/documents/application/artifact_transfer_controller.dart';
import 'package:builder/features/documents/application/document_controller.dart';
import 'package:builder/features/documents/domain/document_models.dart';
import 'package:builder/features/documents/domain/document_problem.dart';
import 'package:builder/features/documents/domain/document_work.dart';
import 'package:builder/features/documents/infrastructure/artifact_file_store.dart';
import 'package:builder/features/documents/infrastructure/document_work_repository.dart';
import 'package:builder/features/documents/presentation/documents_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_files_server.dart';

const owner = 'teacher';

List<int> docxBytes([int size = 20000]) =>
    [0x50, 0x4B, 0x03, 0x04, ...List.generate(size - 4, (i) => i % 251)];

class FakeActions implements ArtifactActions {
  final calls = <String>[];
  OpenOutcome openOutcome = OpenOutcome.opened;
  bool saveAccepted = true;
  List<int>? lastOpenedBytes;

  @override
  Future<OpenOutcome> open(File file, String mimeType) async {
    calls.add('open ${file.uri.pathSegments.last} $mimeType');
    lastOpenedBytes = await file.readAsBytes();
    return openOutcome;
  }

  @override
  Future<bool> save(File file, String fileName, String mimeType) async {
    calls.add('save $fileName $mimeType');
    return saveAccepted;
  }

  @override
  Future<void> share(File file, String fileName, String mimeType) async =>
      calls.add('share $fileName $mimeType');
}

/// Stands in for the real download so the widget test needs no file I/O.
class _StubDownloads extends ArtifactDownloadService {
  _StubDownloads(ArtifactFileStore store) : super(client: null, store: store);
  DocumentProblem? failWith;

  @override
  Future<File> ensureDownloaded(
    String ownerId,
    DocumentArtifact listed, {
    void Function(int received, int total)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    if (failWith != null) throw ArtifactDownloadException(failWith!);
    return File('verified.docx');
  }
}

void main() {
  late Directory temp;
  late FakeFilesServer server;
  late ArtifactFileStore store;
  late FakeActions actions;
  late ProviderContainer container;

  DocumentArtifact artifact() =>
      DocumentArtifact.fromJson(server.artifactJson(server.artifactContent!));

  ArtifactTransferController controller() =>
      container.read(artifactTransferProvider(owner).notifier);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('artifact_tr_');
    server = FakeFilesServer()..artifactContent = docxBytes();
    store = ArtifactFileStore(() async => Directory('${temp.path}/dl'));
    actions = FakeActions();
    container = ProviderContainer(
      overrides: [
        artifactDownloadServiceProvider.overrideWithValue(
          ArtifactDownloadService(client: server.client, store: store),
        ),
        artifactActionsProvider.overrideWithValue(actions),
        artifactFileStoreProvider.overrideWithValue(store),
        documentWorkRepositoryProvider.overrideWithValue(InMemoryDocumentWorkRepository()),
        builderFilesClientProvider.overrideWithValue(server.client),
        documentStagingStoreProvider.overrideWithValue(InMemoryDocumentStagingStore()),
      ],
    );
    // Keep the family alive like a visible screen would.
    container.listen(artifactTransferProvider(owner), (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  group('actions on a downloaded document', () {
    test('open downloads, verifies and hands the verified file to the system', () async {
      final result = await controller().perform(artifact(), ArtifactAction.open);
      expect(result, ArtifactResult.done);
      expect(actions.calls.single, 'open example.docx ${DocumentFormat.docx.mimeType}');
      expect(actions.lastOpenedBytes, server.artifactContent);
      expect(container.read(artifactTransferProvider(owner))[artifactIdFor]!.phase, TransferPhase.ready);
    });

    test('save and share use the document name and type; a cancelled save is not an error', () async {
      expect(await controller().perform(artifact(), ArtifactAction.save), ArtifactResult.saved);
      actions.saveAccepted = false;
      expect(await controller().perform(artifact(), ArtifactAction.save), ArtifactResult.cancelledByUser);
      expect(await controller().perform(artifact(), ArtifactAction.share), ArtifactResult.done);
      expect(actions.calls, [
        'save example.docx ${DocumentFormat.docx.mimeType}',
        'save example.docx ${DocumentFormat.docx.mimeType}',
        'share example.docx ${DocumentFormat.docx.mimeType}',
      ]);
      expect(server.ranges, hasLength(1), reason: 'the verified copy was reused');
    });

    test('no app for the format is reported so the user can save or share instead', () async {
      actions.openOutcome = OpenOutcome.noApp;
      expect(await controller().perform(artifact(), ArtifactAction.open), ArtifactResult.noAppToOpen);
    });

    test('a failed download never reaches the system and shows why', () async {
      server.corruptContent = true;
      final result = await controller().perform(artifact(), ArtifactAction.open);
      expect(result, ArtifactResult.downloadFailed);
      expect(actions.calls, isEmpty);
      final transfer = container.read(artifactTransferProvider(owner))[artifactIdFor]!;
      expect(transfer.phase, TransferPhase.failed);
      expect(transfer.problem, DocumentProblem.integrity);

      server.corruptContent = false;
      expect(await controller().perform(artifact(), ArtifactAction.open), ArtifactResult.done);
    });

    test('cancelling a running download clears its state', () async {
      server.stallAfterBytes = 8192;
      final pending = controller().perform(artifact(), ArtifactAction.open);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(container.read(artifactTransferProvider(owner))[artifactIdFor]!.phase, TransferPhase.downloading);
      controller().cancel(artifactIdFor);
      expect(await pending, ArtifactResult.cancelledByUser);
      expect(container.read(artifactTransferProvider(owner)), isEmpty);
      expect(actions.calls, isEmpty);
    });

    test('a second tap during a download does not start another one', () async {
      server.stallAfterBytes = 8192;
      final first = controller().perform(artifact(), ArtifactAction.open);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await controller().download(artifact()), isNull);
      expect(server.ranges, hasLength(1));
      controller().cancel(artifactIdFor);
      await first;
    });
  });

  group('cleanup of downloaded copies', () {
    DocumentWork finished(DocumentArtifact a) => DocumentWork(
      id: 'w1',
      fileName: 'a.docx',
      sizeBytes: 10,
      skill: DocumentSkill.quiz,
      parameters: const DocumentParameters(language: 'ru'),
      outputs: const [DocumentFormat.docx],
      consentRevision: documentConsentRevision,
      uploadKey: 'u',
      jobKey: 'j',
      stage: DocumentStage.succeeded,
      artifacts: [a],
      createdAtUtc: '2026-10-19T09:00:00Z',
      updatedAtUtc: '2026-10-19T09:00:00Z',
    );

    test('removing a task deletes its downloaded files', () async {
      final repo = container.read(documentWorkRepositoryProvider);
      await repo.save(owner, finished(artifact()));
      await controller().download(artifact());
      expect(Directory('${temp.path}/dl').listSync(recursive: true).whereType<File>(), isNotEmpty);

      container.listen(documentControllerProvider(owner), (_, _) {});
      final docs = container.read(documentControllerProvider(owner).notifier);
      await docs.load();
      await docs.remove('w1');

      expect(Directory('${temp.path}/dl').listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test('opening the list sweeps copies of tasks that no longer exist', () async {
      await controller().download(artifact());
      final orphan = await store.partFile(owner, 'forgotten');
      await orphan.writeAsBytes([1]);

      container.listen(documentControllerProvider(owner), (_, _) {});
      await container.read(documentControllerProvider(owner).notifier).load();

      expect(Directory('${temp.path}/dl').listSync(recursive: true).whereType<File>(), isEmpty,
          reason: 'no task lists the artifact, so nothing is kept');
    });
  });

  testWidgets('the document card downloads on demand and shows why a download failed', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final stub = _StubDownloads(store);
    final repo = InMemoryDocumentWorkRepository();
    await repo.save(owner, DocumentWork(
      id: 'w1',
      fileName: 'a.docx',
      sizeBytes: 10,
      skill: DocumentSkill.quiz,
      parameters: const DocumentParameters(language: 'ru'),
      outputs: const [DocumentFormat.docx],
      consentRevision: documentConsentRevision,
      uploadKey: 'u',
      jobKey: 'j',
      stage: DocumentStage.succeeded,
      artifacts: [artifact()],
      createdAtUtc: '2026-10-19T09:00:00Z',
      updatedAtUtc: '2026-10-19T09:00:00Z',
    ));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentWorkRepositoryProvider.overrideWithValue(repo),
          builderFilesClientProvider.overrideWithValue(server.client),
          artifactDownloadServiceProvider.overrideWithValue(stub),
          artifactActionsProvider.overrideWithValue(actions),
          artifactFileStoreProvider.overrideWithValue(store),
          documentStagingStoreProvider.overrideWithValue(InMemoryDocumentStagingStore()),
        ],
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const DocumentsPage(ownerId: owner),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    stub.failWith = DocumentProblem.integrity;
    await tester.tap(find.byKey(const Key('artifact.save.$artifactIdFor')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('не совпал с данными сервера'), findsOneWidget);
    expect(actions.calls, isEmpty);

    stub.failWith = null;
    await tester.tap(find.byKey(const Key('artifact.save.$artifactIdFor')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(actions.calls.single, startsWith('save example.docx'));
    expect(find.text('Файл сохранён.'), findsOneWidget);
    expect(find.textContaining('не совпал с данными сервера'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
