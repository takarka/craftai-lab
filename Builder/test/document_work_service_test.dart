import 'package:builder/features/documents/application/document_work_service.dart';
import 'package:builder/features/documents/domain/document_models.dart';
import 'package:builder/features/documents/domain/document_problem.dart';
import 'package:builder/features/documents/domain/document_work.dart';
import 'package:builder/features/documents/infrastructure/document_work_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_files_server.dart';

const owner = 'teacher';
const params = DocumentParameters(language: 'ru', topic: 'Дроби', grade: 5, itemsCount: 10);

void main() {
  late FakeFilesServer server;
  late InMemoryDocumentWorkRepository repository;
  late InMemoryDocumentStagingStore staging;
  late DocumentWorkService service;

  setUp(() {
    server = FakeFilesServer();
    repository = InMemoryDocumentWorkRepository();
    staging = InMemoryDocumentStagingStore();
    service = DocumentWorkService(client: server.client, repository: repository, staging: staging);
  });

  Future<DocumentWork> begin({String name = 'урок.docx', List<int>? bytes}) =>
      service.begin(
        ownerId: owner,
        fileName: name,
        bytes: bytes ?? List.filled(2048, 65),
        skill: DocumentSkill.quiz,
        parameters: params,
        outputs: const [DocumentFormat.docx, DocumentFormat.pdf],
        consentRevision: documentConsentRevision,
      );

  Future<DocumentWork> run(DocumentWork work, {int steps = 12}) async {
    var current = work;
    for (var i = 0; i < steps && current.isActive; i++) {
      current = (await service.advance(owner, work.id))!;
    }
    return current;
  }

  group('contract fixtures', () {
    test('valid server objects parse', () {
      expect(DocumentAttachment.fromJson(fixture('Attachment.valid.0')).uploaded, isTrue);
      final job = DocumentJob.fromJson(fixture('DocumentJob.valid.0'));
      expect(job.status, DocumentJobStatus.succeeded);
      expect(job.artifacts.single.format, DocumentFormat.docx);
      final failed = DocumentJob.fromJson(fixture('DocumentJob.valid.1'));
      expect(failed.error!.code, 'job.model-failed');
      expect(failed.error!.retryable, isTrue);
      expect(DocumentArtifact.fromJson(fixture('Artifact.valid.0')).sha256, hasLength(64));
    });

    test('invalid server objects are rejected, not guessed', () {
      for (final name in ['Attachment.invalid.0', 'Attachment.invalid.1']) {
        expect(() => DocumentAttachment.fromJson(fixture(name)), throwsFormatException, reason: name);
      }
      for (final name in ['DocumentJob.invalid.0', 'DocumentJob.invalid.1']) {
        expect(() => DocumentJob.fromJson(fixture(name)), throwsFormatException, reason: name);
      }
      for (final name in ['Artifact.invalid.0', 'Artifact.invalid.1']) {
        expect(() => DocumentArtifact.fromJson(fixture(name)), throwsFormatException, reason: name);
      }
    });

    test('the job request matches the contract example and refuses the invalid ones', () {
      final valid = fixture('CreateDocumentJobRequest.valid.0');
      final body = createDocumentJobBody(
        attachmentId: valid['attachmentId'] as String,
        skill: DocumentSkill.quiz,
        parameters: DocumentParameters(
          language: 'ru',
          topic: (valid['parameters'] as Map)['topic'] as String,
          grade: 7,
          itemsCount: 10,
        ),
        outputs: const [DocumentFormat.docx, DocumentFormat.pdf],
      );
      expect(body, valid);
      expect(() => DocumentSkill.parse(fixture('CreateDocumentJobRequest.invalid.0')['skill']), throwsFormatException);
      expect(() => DocumentFormat.parse((fixture('CreateDocumentJobRequest.invalid.1')['outputs'] as List).first), throwsFormatException);
    });

    test('client-side limits follow the contract', () {
      expect(checkSourceFile('a.docx', 10), isNull);
      expect(checkSourceFile('a.TXT', 10), isNull);
      expect(checkSourceFile('a.pdf', 10), isNull);
      expect(checkSourceFile('a.exe', 10), SourceFileProblem.unsupportedType);
      expect(checkSourceFile('a.docx', 0), SourceFileProblem.empty);
      expect(checkSourceFile('a.docx', maxDocumentBytes + 1), SourceFileProblem.tooLarge);
      expect(safeSourceFileName(r'C:\x\..\отчёт.pdf'), 'отчёт.pdf');
    });
  });

  group('document task', () {
    test('uploads with consent and key, creates the job and ends with artifacts', () async {
      final work = await begin();
      final done = await run(work);

      expect(done.stage, DocumentStage.succeeded);
      expect(done.artifacts.single.fileName, 'example.docx');
      expect(server.lastUploadFields['consentRevision'], documentConsentRevision);
      expect(server.lastUploadContentType, contains(docxMimeType));
      expect(server.requests.firstWhere((r) => r.url.path == '/builder/attachments').headers['Idempotency-Key'], work.uploadKey);
      expect(server.requests.firstWhere((r) => r.url.path == '/builder/document-jobs').headers['Idempotency-Key'], work.jobKey);
      expect(staging.files, isEmpty, reason: 'the client copy is deleted once uploaded');
      expect(done.stagedPath, isNull);
    });

    test('a lost upload answer is repeated with the same key: one attachment', () async {
      final work = await begin();
      server.dropNextUploadAnswer = true;
      final waiting = (await service.advance(owner, work.id))!;
      expect(waiting.stage, DocumentStage.staged);
      expect(waiting.waiting, isTrue);
      expect(waiting.problemCode, DocumentProblem.noNetwork.code);
      expect(staging.files, isNotEmpty, reason: 'the copy is kept to repeat the upload');

      final done = await run(waiting);
      expect(done.stage, DocumentStage.succeeded);
      expect(server.count('POST', '/builder/attachments'), 2);
      expect(server.attachmentsCreated, 1);
    });

    test('a lost job answer is repeated with the same key: one job', () async {
      final work = await begin();
      server.dropNextJobAnswer = true;
      final done = await run(work, steps: 20);
      expect(done.stage, DocumentStage.succeeded);
      expect(server.count('POST', '/builder/document-jobs'), 2);
      expect(server.jobsCreated, 1);
    });

    test('losing the connection while waiting keeps the task and resumes later', () async {
      final work = await begin();
      await service.advance(owner, work.id);
      await service.advance(owner, work.id);
      server.offline = true;
      final waiting = (await service.advance(owner, work.id))!;
      expect(waiting.isActive, isTrue);
      expect(waiting.waiting, isTrue);
      server.offline = false;
      expect((await run(waiting)).stage, DocumentStage.succeeded);
    });

    test('an encrypted or scanned file is refused with its own reason and nothing is left', () async {
      for (final (status, code, problem) in [
        (422, 'file.no-text-layer', DocumentProblem.noTextLayer),
        (422, 'file.encrypted', DocumentProblem.encrypted),
        (422, 'file.corrupt', DocumentProblem.corrupt),
        (422, 'file.partial-text', DocumentProblem.partialText),
        (422, 'file.limits-exceeded', DocumentProblem.limitsExceeded),
        (413, 'file.too-large', DocumentProblem.tooLarge),
        (415, 'file.unsupported-type', DocumentProblem.unsupportedType),
        (409, 'consent.required', DocumentProblem.consentRequired),
      ]) {
        final fresh = FakeFilesServer()..uploadError = (status, code);
        final svc = DocumentWorkService(client: fresh.client, repository: repository, staging: staging);
        final work = await svc.begin(
          ownerId: owner,
          fileName: 'scan.pdf',
          bytes: List.filled(100, 1),
          skill: DocumentSkill.lessonPlan,
          parameters: const DocumentParameters(language: 'kk'),
          outputs: const [DocumentFormat.pdf],
          consentRevision: documentConsentRevision,
        );
        final result = (await svc.advance(owner, work.id))!;
        expect(result.stage, DocumentStage.failed, reason: code);
        expect(DocumentProblem.fromCode(result.problemCode), problem, reason: code);
        expect(fresh.count('POST', '/builder/document-jobs'), 0, reason: code);
      }
      expect(staging.files, isEmpty);
    });

    test('an attachment the server rejected never becomes a job', () async {
      server.rejectUploadedAttachment = true;
      final done = await run(await begin());
      expect(done.stage, DocumentStage.failed);
      expect(done.problemCode, DocumentProblem.encrypted.code);
      expect(server.count('POST', '/builder/document-jobs'), 0);
    });

    test('a failed job reports the server reason', () async {
      server.jobFailsWith = 'job.build-failed';
      final done = await run(await begin());
      expect(done.stage, DocumentStage.failed);
      expect(DocumentProblem.fromCode(done.problemCode), DocumentProblem.buildFailed);
      expect(done.artifacts, isEmpty);
    });

    test('a job that "succeeded" without files is not shown as a result', () async {
      server.succeedWithoutArtifacts = true;
      final done = await run(await begin());
      expect(done.stage, DocumentStage.failed);
      expect(done.artifacts, isEmpty);
    });

    test('a job the server no longer knows ends as expired', () async {
      final work = await begin();
      await service.advance(owner, work.id);
      await service.advance(owner, work.id);
      server.jobExpired = true;
      final result = (await service.advance(owner, work.id))!;
      expect(result.stage, DocumentStage.failed);
      expect(result.problemCode, DocumentProblem.expired.code);
    });

    test('cancel before upload is local: no request, no copy left', () async {
      final work = await begin();
      final canceled = (await service.requestCancel(owner, work.id))!;
      expect(canceled.stage, DocumentStage.canceled);
      expect(server.requests, isEmpty);
      expect(staging.files, isEmpty);
    });

    test('cancel with a running job asks the server and ends when it confirms', () async {
      final work = await begin();
      await service.advance(owner, work.id);
      await service.advance(owner, work.id);
      final canceled = (await service.requestCancel(owner, work.id))!;
      expect(server.count('POST', '/cancel'), 1);
      expect(canceled.stage, DocumentStage.canceled);
    });

    test('invalid files and settings are refused before anything is stored', () async {
      for (final (name, bytes) in [
        ('a.exe', List.filled(10, 1)),
        ('a.docx', <int>[]),
        ('a.pdf', List.filled(maxDocumentBytes + 1, 1)),
      ]) {
        await expectLater(begin(name: name, bytes: bytes), throwsA(isA<DocumentStartException>()), reason: name);
      }
      await expectLater(
        service.begin(
          ownerId: owner,
          fileName: 'a.txt',
          bytes: [1],
          skill: DocumentSkill.quiz,
          parameters: const DocumentParameters(language: 'en'),
          outputs: const [DocumentFormat.pdf],
          consentRevision: documentConsentRevision,
        ),
        throwsArgumentError,
      );
      expect(await repository.list(owner), isEmpty);
      expect(staging.files, isEmpty);
      expect(server.requests, isEmpty);
    });

    test('removing a task deletes the server job and attachment', () async {
      final work = await run(await begin());
      await service.remove(owner, work.id);
      expect(server.count('DELETE', '/builder/document-jobs'), 1);
      expect(server.count('DELETE', '/builder/attachments'), 1);
      expect(await repository.list(owner), isEmpty);
    });

    test('clearOwner removes only that owner\'s tasks, files and server copies', () async {
      final mine = await begin();
      await service.advance(owner, mine.id);
      final other = await service.begin(
        ownerId: 'other',
        fileName: 'b.txt',
        bytes: [1, 2, 3],
        skill: DocumentSkill.quiz,
        parameters: const DocumentParameters(language: 'ru'),
        outputs: const [DocumentFormat.docx],
        consentRevision: documentConsentRevision,
      );

      await service.clearOwner(owner);

      expect(await repository.list(owner), isEmpty);
      expect((await repository.list('other')).single.id, other.id);
      expect(staging.files.keys.single, contains('other'));
      expect(server.count('DELETE', '/builder/attachments'), 1);
    });

    test('without an API client the task waits instead of failing', () async {
      final offline = DocumentWorkService(client: null, repository: repository, staging: staging);
      final work = await begin();
      final result = (await offline.advance(owner, work.id))!;
      expect(result.isActive, isTrue);
      expect(result.waiting, isTrue);
    });
  });
}
