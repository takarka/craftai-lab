import 'dart:convert';
import 'dart:io';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/files/file_staging_journal.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/security/storage_cipher.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/onboarding/domain/assistant_setup.dart';
import 'package:builder/features/onboarding/domain/initial_workspace_repository.dart';
import 'package:builder/features/onboarding/infrastructure/persistent_initial_workspace_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('StorageCipher', () {
    final key = List<int>.generate(32, (i) => i * 7 % 256);
    final cipher = StorageCipher(key: key);

    test('encrypts and decrypts UTF-8 plaintext correctly', () {
      const plaintext = 'Секретная инструкция ассистента: Құпия мәлімет';
      final encrypted = cipher.encrypt(plaintext);
      expect(encrypted, isNot(plaintext));

      final decrypted = cipher.decrypt(encrypted);
      expect(decrypted, equals(plaintext));
    });

    test('fails on tampered ciphertext (integrity verification)', () {
      const plaintext = 'Protected text';
      final encrypted = cipher.encrypt(plaintext);
      final raw = base64Decode(encrypted);
      raw[raw.length - 1] ^= 0xFF; // tamper with last byte
      final tampered = base64Encode(raw);

      expect(
        () => cipher.decrypt(tampered),
        throwsA(isA<CipherDecryptionException>()),
      );
    });

    test('fails when decrypting with a different key', () {
      const plaintext = 'Protected text';
      final encrypted = cipher.encrypt(plaintext);
      final wrongKey = List<int>.generate(32, (i) => (i + 1) * 3 % 256);
      final wrongCipher = StorageCipher(key: wrongKey);

      expect(
        () => wrongCipher.decrypt(encrypted),
        throwsA(isA<CipherDecryptionException>()),
      );
    });
  });

  group('StorageDatabase & Schema V1', () {
    late Directory tempDir;
    late String dbPath;
    late StorageDatabase storageDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('storage_test_');
      dbPath = p.join(tempDir.path, 'test_builder.db');
      storageDb = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await storageDb.open();
    });

    tearDown(() async {
      await storageDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates all 18 tables from schema version 1', () async {
      final tables = await storageDb.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
      );
      final tableNames = tables.map((r) => r['name'] as String).toSet();

      expect(
        tableNames,
        containsAll([
          StorageSchemaV1.tableWorkspaces,
          StorageSchemaV1.tableTeacherPreferences,
          StorageSchemaV1.tableAssistantConfigurations,
          StorageSchemaV1.tableInstructionRules,
          StorageSchemaV1.tableAssistantVersions,
          StorageSchemaV1.tableConversations,
          StorageSchemaV1.tableMessages,
          StorageSchemaV1.tableRequestTraces,
          StorageSchemaV1.tableKnowledgeDocuments,
          StorageSchemaV1.tableDocumentRevisions,
          StorageSchemaV1.tableKnowledgeChunks,
          StorageSchemaV1.tableMemoryFacts,
          StorageSchemaV1.tableToolGrants,
          StorageSchemaV1.tablePendingActions,
          StorageSchemaV1.tableToolInvocations,
          StorageSchemaV1.tableCourseProgress,
          StorageSchemaV1.tableQuizAttempts,
          StorageSchemaV1.tableFileStagingJournal,
        ]),
      );
    });

    test('enforces foreign key constraints', () async {
      // Trying to insert preferences for a non-existent workspace should fail
      expect(
        () => storageDb.db.insert(StorageSchemaV1.tableTeacherPreferences, {
          'owner_id': 'missing_owner',
          'subject': 'mathematics',
          'grades_json': '[5, 6]',
          'ui_language': 'ru',
          'assistant_language': 'russian',
          'updated_at_utc': DateTime.now().toUtc().toIso8601String(),
        }),
        throwsA(anything),
      );
    });

    test('does not delete database on corrupt file error', () async {
      await storageDb.close();
      // Corrupt the database file
      await File(dbPath).writeAsString('CORRUPTED_NON_SQLITE_DATA');

      final corruptDb = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );

      expect(
        () => corruptDb.open(),
        throwsA(isA<StorageCorruptionException>()),
      );
      // Verify file still exists so recovery/support can inspect it
      expect(await File(dbPath).exists(), isTrue);
    });
  });

  group('PersistentInitialWorkspaceRepository', () {
    late Directory tempDir;
    late StorageDatabase storageDb;
    late PersistentInitialWorkspaceRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('repo_test_');
      final dbPath = p.join(tempDir.path, 'repo_builder.db');
      storageDb = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await storageDb.open();
      repository = PersistentInitialWorkspaceRepository(
        database: storageDb,
        installationId: 'test_inst_1',
      );
    });

    tearDown(() async {
      await storageDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'creates initial workspace atomically when permit is current',
      () async {
        var permitActive = true;
        final permit = WorkspaceWritePermit(
          ownerId: 'teacher_user_42',
          canCommit: () => permitActive,
        );

        final setup = AssistantSetup(
          subject: SchoolSubject.mathematics,
          grades: {5, 6, 7},
          language: AssistantLanguage.russian,
          name: 'Алгебра-Бот',
        );

        final created = await repository.createIfAbsent(
          permit: permit,
          setup: setup,
        );

        expect(created.ownerId, equals('teacher_user_42'));
        expect(created.setup.name, equals('Алгебра-Бот'));
        expect(created.setup.subject, equals(SchoolSubject.mathematics));
        expect(created.setup.grades, equals({5, 6, 7}));

        // Verify records in DB
        final wsRows = await storageDb.db.query(
          StorageSchemaV1.tableWorkspaces,
        );
        expect(wsRows.length, equals(1));
        expect(wsRows.first['owner_id'], equals('teacher_user_42'));
        expect(wsRows.first['workspace_epoch'], equals(1));

        final prefRows = await storageDb.db.query(
          StorageSchemaV1.tableTeacherPreferences,
        );
        expect(prefRows.length, equals(1));
        expect(prefRows.first['subject'], equals('mathematics'));

        final confRows = await storageDb.db.query(
          StorageSchemaV1.tableAssistantConfigurations,
        );
        expect(confRows.length, equals(1));
        expect(confRows.first['name'], equals('Алгебра-Бот'));
      },
    );

    test(
      'aborts transaction if permit becomes invalid before commit',
      () async {
        var permitActive = false; // revoked permit
        final permit = WorkspaceWritePermit(
          ownerId: 'teacher_user_revoked',
          canCommit: () => permitActive,
        );

        final setup = AssistantSetup(
          subject: SchoolSubject.physics,
          grades: {9},
          name: 'Физ-Бот',
        );

        expect(
          () => repository.createIfAbsent(permit: permit, setup: setup),
          throwsA(isA<PermitRevokedException>()),
        );

        // Verify no records committed
        final wsRows = await storageDb.db.query(
          StorageSchemaV1.tableWorkspaces,
        );
        expect(wsRows, isEmpty);
      },
    );

    test(
      'is idempotent: subsequent calls for same owner return existing setup without duplicate',
      () async {
        final permit = WorkspaceWritePermit(
          ownerId: 'teacher_user_repeat',
          canCommit: () => true,
        );

        final setup1 = AssistantSetup(
          subject: SchoolSubject.chemistry,
          grades: {8},
          name: 'Химия-1',
        );
        final firstResult = await repository.createIfAbsent(
          permit: permit,
          setup: setup1,
        );
        expect(firstResult.setup.name, equals('Химия-1'));

        final setup2 = AssistantSetup(
          subject: SchoolSubject.biology,
          grades: {10},
          name: 'Химия-Overwritten?',
        );
        final secondResult = await repository.createIfAbsent(
          permit: permit,
          setup: setup2,
        );

        // Should return original created setup, not overwritten
        expect(secondResult.ownerId, equals('teacher_user_repeat'));
        expect(secondResult.setup.name, equals('Химия-1'));
        expect(secondResult.setup.subject, equals(SchoolSubject.chemistry));

        final count = await storageDb.db.query(StorageSchemaV1.tableWorkspaces);
        expect(count.length, equals(1));
      },
    );

    test('isolates different owners cleanly', () async {
      final permit1 = WorkspaceWritePermit(
        ownerId: 'owner_A',
        canCommit: () => true,
      );
      final permit2 = WorkspaceWritePermit(
        ownerId: 'owner_B',
        canCommit: () => true,
      );

      await repository.createIfAbsent(
        permit: permit1,
        setup: AssistantSetup(
          subject: SchoolSubject.russian,
          grades: {1},
          name: 'Бот А',
        ),
      );
      await repository.createIfAbsent(
        permit: permit2,
        setup: AssistantSetup(
          subject: SchoolSubject.kazakh,
          grades: {11},
          name: 'Бот Б',
        ),
      );

      final wsRows = await storageDb.db.query(StorageSchemaV1.tableWorkspaces);
      expect(wsRows.length, equals(2));

      final owners = wsRows.map((r) => r['owner_id']).toSet();
      expect(owners, containsAll(['owner_A', 'owner_B']));
    });
  });

  group('WorkspaceStorageService & Isolation', () {
    late Directory tempDir;
    late StorageDatabase storageDb;
    late WorkspaceStorageService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('service_test_');
      final dbPath = p.join(tempDir.path, 'service_builder.db');
      storageDb = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await storageDb.open();
      service = WorkspaceStorageService(
        database: storageDb,
        keyStorage: InMemorySecureKeyStorage(),
        installationId: 'inst_test',
      );
    });

    tearDown(() async {
      await storageDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'switches owner, purges in-memory caches, and creates new epoch',
      () async {
        final infoA = await service.openWorkspace(ownerId: 'owner_1');
        expect(infoA.ownerId, equals('owner_1'));
        expect(infoA.workspaceEpoch, equals(1));

        service.inMemoryCache['cached_token'] = 'token_for_owner_1';
        expect(
          service.inMemoryCache['cached_token'],
          equals('token_for_owner_1'),
        );

        // Switch to owner_2
        final infoB = await service.openWorkspace(ownerId: 'owner_2');
        expect(infoB.ownerId, equals('owner_2'));
        expect(infoB.workspaceEpoch, equals(1));

        // Cache from owner_1 must be wiped
        expect(service.inMemoryCache.containsKey('cached_token'), isFalse);

        // Close workspace
        await service.closeActiveWorkspace();
        expect(service.hasActiveWorkspace, isFalse);
        expect(() => service.inMemoryCache, throwsA(isA<StateError>()));
      },
    );

    test('bumping epoch invalidates previous epoch', () async {
      await service.openWorkspace(ownerId: 'owner_epoch');
      expect(service.activeEpoch, equals(1));

      final newEpoch = await service.bumpWorkspaceEpoch(ownerId: 'owner_epoch');
      expect(newEpoch, equals(2));
      expect(service.activeEpoch, equals(2));

      final row = await storageDb.db.query(
        StorageSchemaV1.tableWorkspaces,
        where: 'owner_id = ?',
        whereArgs: ['owner_epoch'],
      );
      expect(row.first['workspace_epoch'], equals(2));
    });

    test('purges all owner data and files completely', () async {
      await service.openWorkspace(ownerId: 'to_delete');
      final ownerDir = p.join(tempDir.path, 'owner_files_to_delete');
      await Directory(ownerDir).create(recursive: true);
      await File(p.join(ownerDir, 'test.txt')).writeAsString('sensitive data');

      await service.purgeOwnerData(
        ownerId: 'to_delete',
        ownerFilesDir: ownerDir,
      );

      final ws = await storageDb.db.query(
        StorageSchemaV1.tableWorkspaces,
        where: 'owner_id = ?',
        whereArgs: ['to_delete'],
      );
      expect(ws, isEmpty);
      expect(await Directory(ownerDir).exists(), isFalse);
    });
  });

  group('FileStagingJournal', () {
    late Directory tempDir;
    late StorageDatabase storageDb;
    const journal = FileStagingJournal();

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('staging_test_');
      final dbPath = p.join(tempDir.path, 'staging_builder.db');
      storageDb = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await storageDb.open();
    });

    tearDown(() async {
      await storageDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('stages file and commits atomically to destination', () async {
      final stagingPath = p.join(tempDir.path, 'stage.tmp');
      final targetPath = p.join(tempDir.path, 'docs', 'final.txt');

      await File(stagingPath).writeAsString('Hello Staging');

      await journal.recordStaging(
        db: storageDb.db,
        id: 'stage_1',
        ownerId: 'owner_stg',
        stagingPath: stagingPath,
        targetPath: targetPath,
      );

      await journal.commitStagedFile(
        db: storageDb.db,
        id: 'stage_1',
        stagingPath: stagingPath,
        targetPath: targetPath,
      );

      expect(await File(targetPath).exists(), isTrue);
      expect(await File(targetPath).readAsString(), equals('Hello Staging'));
      expect(await File(stagingPath).exists(), isFalse);

      final row = await storageDb.db.query(
        StorageSchemaV1.tableFileStagingJournal,
        where: 'id = ?',
        whereArgs: ['stage_1'],
      );
      expect(row.first['status'], equals(StagingStatus.committed.name));
    });

    test(
      'recovers interrupted staging by cleaning orphaned files on startup',
      () async {
        final stagingPath = p.join(tempDir.path, 'abandoned.tmp');
        final targetPath = p.join(tempDir.path, 'never_committed.txt');
        await File(stagingPath).writeAsString('Interrupted write content');

        await journal.recordStaging(
          db: storageDb.db,
          id: 'stage_interrupted',
          ownerId: 'owner_crash',
          stagingPath: stagingPath,
          targetPath: targetPath,
        );

        final cleaned = await journal.recoverInterruptedStaging(storageDb.db);
        expect(cleaned, equals(1));
        expect(await File(stagingPath).exists(), isFalse);

        final row = await storageDb.db.query(
          StorageSchemaV1.tableFileStagingJournal,
          where: 'id = ?',
          whereArgs: ['stage_interrupted'],
        );
        expect(row.first['status'], equals(StagingStatus.aborted.name));
      },
    );
  });
}
