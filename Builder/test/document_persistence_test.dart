import 'dart:io';

import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/documents/application/document_work_service.dart';
import 'package:builder/features/documents/domain/document_models.dart';
import 'package:builder/features/documents/domain/document_work.dart';
import 'package:builder/features/documents/infrastructure/document_work_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_files_server.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temp;
  late StorageDatabase storage;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('document_work_');
    storage = StorageDatabase(
      databasePath: '${temp.path}/doc.db',
      databaseFactory: databaseFactoryFfi,
    );
    await storage.open();
    final now = DateTime.now().toUtc().toIso8601String();
    for (final owner in ['a', 'b']) {
      await storage.db.insert(StorageSchemaV1.tableWorkspaces, {
        'owner_id': owner,
        'installation_id': 'i',
        'schema_version': 1,
        'workspace_epoch': 1,
        'created_at_utc': now,
        'updated_at_utc': now,
      });
    }
  });

  tearDown(() async {
    if (storage.isOpen) await storage.close();
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  DocumentWorkService service(FakeFilesServer server, DocumentStagingStore staging) =>
      DocumentWorkService(
        client: server.client,
        repository: PersistentDocumentWorkRepository(database: storage),
        staging: staging,
      );

  test('a task survives a restart and continues with the same keys', () async {
    final staging = FileDocumentStagingStore(() async => Directory('${temp.path}/uploads'));
    final server = FakeFilesServer();
    final first = service(server, staging);
    final work = await first.begin(
      ownerId: 'a',
      fileName: 'урок.pdf',
      bytes: List.filled(2048, 7),
      skill: DocumentSkill.lessonPlan,
      parameters: const DocumentParameters(language: 'kk', topic: 'Тақырып', grade: 6),
      outputs: const [DocumentFormat.pdf],
      consentRevision: documentConsentRevision,
    );
    server.dropNextUploadAnswer = true;
    await first.advance('a', work.id);

    // "Restart": new service objects over the same database and files.
    final restarted = service(server, staging);
    final stored = (await PersistentDocumentWorkRepository(database: storage).list('a')).single;
    expect(stored.uploadKey, work.uploadKey);
    expect(stored.stage, DocumentStage.staged);
    expect(stored.parameters.topic, 'Тақырып');
    expect(stored.outputs, [DocumentFormat.pdf]);

    var current = stored;
    for (var i = 0; i < 12 && current.isActive; i++) {
      current = (await restarted.advance('a', work.id))!;
    }
    expect(current.stage, DocumentStage.succeeded);
    expect(server.attachmentsCreated, 1, reason: 'no duplicate after the restart');
    expect(server.jobsCreated, 1);
    expect(Directory('${temp.path}/uploads').listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('tasks are isolated by owner and removed with the owner', () async {
    final repo = PersistentDocumentWorkRepository(database: storage);
    final staging = InMemoryDocumentStagingStore();
    final svc = service(FakeFilesServer(), staging);
    for (final owner in ['a', 'b']) {
      await svc.begin(
        ownerId: owner,
        fileName: '$owner.txt',
        bytes: [1, 2, 3],
        skill: DocumentSkill.quiz,
        parameters: const DocumentParameters(language: 'ru'),
        outputs: const [DocumentFormat.docx],
        consentRevision: documentConsentRevision,
      );
    }
    expect((await repo.list('a')).single.fileName, 'a.txt');
    expect((await repo.list('b')).single.fileName, 'b.txt');

    await WorkspaceStorageService(
      database: storage,
      keyStorage: InMemorySecureKeyStorage(),
      installationId: 'i',
    ).purgeOwnerData(ownerId: 'a');

    expect(await repo.list('a'), isEmpty);
    expect((await repo.list('b')).single.fileName, 'b.txt');
  });

  test('the staging store keeps the original name out of the path and cleans per owner', () async {
    final root = Directory('${temp.path}/stage');
    final store = FileDocumentStagingStore(() async => root);
    final path = await store.write('a/../b', 'w1', '../../секрет.docx', [1, 2, 3]);
    expect(path, startsWith(root.path));
    expect(path.contains('секрет'), isFalse);
    expect(await store.read(path), [1, 2, 3]);

    await store.write('other', 'w2', 'x.txt', [9]);
    await store.deleteOwner('a/../b');
    expect(await store.read(path), isNull);
    expect(root.listSync().length, 1, reason: 'the other owner is untouched');

    await store.delete('other', 'w2');
    expect(await store.read('${root.path}/other/w2/source.bin'), isNull);
  });
}
