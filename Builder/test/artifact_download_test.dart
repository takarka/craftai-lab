import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:builder/features/documents/application/artifact_download_service.dart';
import 'package:builder/features/documents/domain/document_models.dart';
import 'package:builder/features/documents/domain/document_problem.dart';
import 'package:builder/features/documents/infrastructure/artifact_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_files_server.dart';

const owner = 'teacher';

/// A body that looks like a DOCX (ZIP signature) or PDF and spans several chunks.
List<int> docxBytes([int size = 20000]) =>
    [0x50, 0x4B, 0x03, 0x04, ...List.generate(size - 4, (i) => i % 251)];
List<int> pdfBytes([int size = 9000]) =>
    [...'%PDF-1.7\n'.codeUnits, ...List.generate(size - 9, (i) => 32 + i % 90)];

void main() {
  late Directory temp;
  late FakeFilesServer server;
  late ArtifactFileStore store;
  late ArtifactDownloadService service;

  DocumentArtifact artifact([List<int>? content]) =>
      DocumentArtifact.fromJson(server.artifactJson(content ?? server.artifactContent!));

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('artifact_dl_');
    server = FakeFilesServer()..artifactContent = docxBytes();
    store = ArtifactFileStore(() async => Directory('${temp.path}/dl'));
    service = ArtifactDownloadService(client: server.client, store: store);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  List<File> filesOf() => Directory('${temp.path}/dl').existsSync()
      ? Directory('${temp.path}/dl').listSync(recursive: true).whereType<File>().toList()
      : [];

  test('downloads, verifies and reports progress; the final file has the document name', () async {
    final progress = <int>[];
    final file = await service.ensureDownloaded(
      owner,
      artifact(),
      onProgress: (received, total) => progress.add(received),
    );
    expect(file.path, endsWith('example.docx'));
    expect(await file.readAsBytes(), server.artifactContent);
    expect(progress.first, 0);
    expect(progress.last, server.artifactContent!.length);
    expect(progress, orderedEquals([...progress]..sort()));
    expect(filesOf().map((f) => f.path.split(RegExp(r'[\\/]')).last), ['example.docx'],
        reason: 'no .part left');
  });

  test('a verified local copy is reused without touching the network', () async {
    await service.ensureDownloaded(owner, artifact());
    final before = server.requests.length;
    await service.ensureDownloaded(owner, artifact());
    expect(server.requests.length, before);
  });

  test('a PDF is accepted with its own signature', () async {
    server
      ..artifactContent = pdfBytes()
      ..artifactFormat = 'pdf';
    final file = await service.ensureDownloaded(owner, artifact());
    expect(file.path, endsWith('example.pdf'));
  });

  test('an interrupted download is resumed with Range, not restarted', () async {
    server.dropAfterBytes = 8192;
    await expectLater(
      service.ensureDownloaded(owner, artifact()),
      throwsA(isA<ArtifactDownloadException>().having((e) => e.problem, 'problem', DocumentProblem.noNetwork)),
    );
    final partial = filesOf().single;
    expect(partial.path, endsWith('download.part'), reason: 'never published under the final name');
    final stored = partial.lengthSync();
    expect(stored, greaterThan(0));
    expect(stored, lessThan(server.artifactContent!.length));

    server.dropAfterBytes = null;
    final file = await service.ensureDownloaded(owner, artifact());
    expect(server.ranges.last, 'bytes=$stored-');
    expect(await file.readAsBytes(), server.artifactContent);
    expect(server.contentBytesSent, server.artifactContent!.length,
        reason: 'only the missing bytes were sent the second time');
  });

  test('a server that ignores Range restarts cleanly instead of corrupting the file', () async {
    server.dropAfterBytes = 8192;
    await expectLater(service.ensureDownloaded(owner, artifact()), throwsA(isA<ArtifactDownloadException>()));
    server
      ..dropAfterBytes = null
      ..ignoreRange = true;
    final file = await service.ensureDownloaded(owner, artifact());
    expect(await file.readAsBytes(), server.artifactContent);
  });

  test('a file that does not match the hash is deleted and never shown', () async {
    server.corruptContent = true;
    await expectLater(
      service.ensureDownloaded(owner, artifact()),
      throwsA(isA<ArtifactDownloadException>().having((e) => e.problem, 'problem', DocumentProblem.integrity)),
    );
    expect(filesOf(), isEmpty);
  });

  test('error text delivered as "content" is not accepted even if its hash matches', () async {
    final page = '{"code":"job.build-failed","message":"Internal error"}'.codeUnits;
    server.artifactContent = page;
    await expectLater(
      service.ensureDownloaded(owner, artifact()),
      throwsA(isA<ArtifactDownloadException>().having((e) => e.problem, 'problem', DocumentProblem.integrity)),
    );
    expect(filesOf(), isEmpty);
  });

  test('metadata that disagrees with the job listing is refused', () async {
    final listed = artifact();
    server.artifactContent = docxBytes(25000);
    await expectLater(
      service.ensureDownloaded(owner, listed),
      throwsA(isA<ArtifactDownloadException>().having((e) => e.problem, 'problem', DocumentProblem.integrity)),
    );
    expect(server.ranges, isEmpty, reason: 'no bytes were downloaded');
  });

  test('an expired artifact is reported without downloading', () async {
    final listed = DocumentArtifact.fromJson({
      ...artifact().toJson(),
      'expiresAtUtc': '2020-01-01T00:00:00Z',
    });
    await expectLater(
      service.ensureDownloaded(owner, listed),
      throwsA(isA<ArtifactDownloadException>().having((e) => e.problem, 'problem', DocumentProblem.artifactExpired)),
    );
    expect(server.requests, isEmpty);

    server.artifactMetaExpired = true;
    await expectLater(
      service.ensureDownloaded(owner, artifact()),
      throwsA(isA<ArtifactDownloadException>().having((e) => e.problem, 'problem', DocumentProblem.artifactExpired)),
    );
  });

  test('losing the session or the server are reported as such', () async {
    server.offline = true;
    await expectLater(
      service.ensureDownloaded(owner, artifact()),
      throwsA(isA<ArtifactDownloadException>().having((e) => e.problem, 'problem', DocumentProblem.noNetwork)),
    );
    final noClient = ArtifactDownloadService(client: null, store: store);
    await expectLater(
      noClient.ensureDownloaded(owner, artifact()),
      throwsA(isA<ArtifactDownloadException>().having((e) => e.problem, 'problem', DocumentProblem.auth)),
    );
  });

  test('a full disk is reported and the partial file is removed', () async {
    final failing = ArtifactDownloadService(
      client: server.client,
      store: store,
      openSink: (part, mode) => _FullDiskSink(part.openWrite(mode: mode)),
    );
    await expectLater(
      failing.ensureDownloaded(owner, artifact()),
      throwsA(isA<ArtifactDownloadException>().having((e) => e.problem, 'problem', DocumentProblem.noSpace)),
    );
    expect(filesOf(), isEmpty);
  });

  test('cancelling stops the download and keeps no file', () async {
    server.stallAfterBytes = 8192;
    final abort = Completer<void>();
    final pending = service.ensureDownloaded(owner, artifact(), abortTrigger: abort.future);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    abort.complete();
    await expectLater(pending, throwsA(isA<ArtifactDownloadCancelled>()));
    expect(filesOf(), isEmpty);
  });

  group('cleanup', () {
    test('sweep keeps listed copies and removes the rest and any partial file', () async {
      final keep = artifact();
      await service.ensureDownloaded(owner, keep);
      await store.partFile(owner, keep.id).then((f) => f.writeAsBytes([1]));
      final stray = await store.partFile(owner, 'stray-id');
      await stray.writeAsBytes([1, 2]);

      await store.sweep(owner, {keep.id});

      final names = filesOf().map((f) => f.path.split(RegExp(r'[\\/]')).last).toList();
      expect(names, ['example.docx']);
    });

    test('deleteOwner removes only that owner', () async {
      await service.ensureDownloaded(owner, artifact());
      final other = await store.partFile('other', 'x');
      await other.writeAsBytes([1]);
      await store.deleteOwner(owner);
      expect(filesOf().single.path, contains('other'));
    });

    test('the local name is safe and keeps the document extension', () {
      final tricky = DocumentArtifact.fromJson({
        ...artifact().toJson(),
        'fileName': '../../etc/план урока',
      });
      expect(ArtifactFileStore.localName(tricky), 'план урока.docx');
    });
  });
}

/// Writes nothing and fails like a full disk on flush.
class _FullDiskSink implements IOSink {
  _FullDiskSink(this._inner);
  final IOSink _inner;

  @override
  Encoding encoding = utf8;
  @override
  void add(List<int> data) {}
  @override
  Future<void> flush() async => throw const FileSystemException(
    'write failed',
    '',
    OSError('No space left on device', 28),
  );
  @override
  Future<void> close() => _inner.close();
  @override
  Future<void> get done => _inner.done;
  @override
  void write(Object? object) {}
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? object = '']) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<dynamic> addStream(Stream<List<int>> stream) async {}
}
