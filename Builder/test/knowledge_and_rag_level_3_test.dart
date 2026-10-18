import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/storage_providers.dart';
import 'package:builder/features/chat/domain/context_assembler.dart';
import 'package:builder/features/knowledge/domain/chunker.dart';
import 'package:builder/features/knowledge/domain/knowledge_models.dart';
import 'package:builder/features/knowledge/domain/local_embedder.dart';
import 'package:builder/features/knowledge/domain/text_extractor.dart';
import 'package:builder/features/knowledge/infrastructure/persistent_knowledge_repository.dart';
import 'package:builder/features/knowledge/presentation/knowledge_page.dart';
import 'package:builder/features/knowledge/presentation/knowledge_providers.dart';
import 'package:builder/features/trace/domain/request_trace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Uint8List createMockDocxBytes(String text) {
  final escapedText = text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  final documentXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r>
        <w:t>$escapedText</w:t>
      </w:r>
    </w:p>
  </w:body>
</w:document>''';

  final archive = Archive();
  final bytes = utf8.encode(documentXml);
  archive.addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List createMockPdfBytes(String text) {
  final cleanText = text.replaceAll('(', '[').replaceAll(')', ']');
  final pdfContent =
      '%PDF-1.4\n'
      '1 0 obj\n'
      '<< /Type /Catalog /Pages 2 0 R >>\n'
      'endobj\n'
      '2 0 obj\n'
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>\n'
      'endobj\n'
      '3 0 obj\n'
      '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\n'
      'endobj\n'
      '4 0 obj\n'
      '<< /Length ${cleanText.length + 20} >>\n'
      'stream\n'
      'BT\n'
      '/F1 12 Tf\n'
      '($cleanText) Tj\n'
      'ET\n'
      'endstream\n'
      'endobj\n'
      'xref\n'
      '0 5\n'
      '0000000000 65535 f \n'
      'trailer\n'
      '<< /Root 1 0 R >>\n'
      '%%EOF';
  return Uint8List.fromList(utf8.encode(pdfContent));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('F12-03 & F12-04: Text Extraction', () {
    test(
      'TXT extraction supports UTF-8 and handles empty text error',
      () async {
        final sampleTxt = Uint8List.fromList(
          utf8.encode('Учебный план на 2026 год. Раздел 1. Введение.'),
        );
        final extracted = await TextExtractor.extract(
          bytes: sampleTxt,
          format: DocumentFormat.txt,
          fileName: 'plan.txt',
        );

        expect(extracted.fullText, contains('Учебный план на 2026 год'));
        expect(extracted.pages.length, 1);

        // Empty text throws DocumentProcessingException
        expect(
          () => TextExtractor.extract(
            bytes: Uint8List(0),
            format: DocumentFormat.txt,
            fileName: 'empty.txt',
          ),
          throwsA(isA<DocumentProcessingException>()),
        );
      },
    );

    test(
      'DOCX extraction extracts word/document.xml text without macros',
      () async {
        final sampleDocx = createMockDocxBytes(
          'Расписание уроков 7 «Б» класса. Понедельник: 1. Алгебра, 2. Физика.',
        );
        final extracted = await TextExtractor.extract(
          bytes: sampleDocx,
          format: DocumentFormat.docx,
          fileName: 'Расписание_7Б.docx',
        );

        expect(extracted.fullText, contains('Расписание уроков 7 «Б» класса'));
        expect(extracted.fullText, contains('Алгебра'));
      },
    );

    test(
      'PDF extraction parses text and flags password-protected or scanned docs',
      () async {
        final samplePdf = createMockPdfBytes(
          'Рабочая программа по биологии для 7 класса. Клетка и ткани.',
        );
        final extracted = await TextExtractor.extract(
          bytes: samplePdf,
          format: DocumentFormat.pdf,
          fileName: 'Биология_программа.pdf',
        );

        expect(extracted.fullText, contains('Рабочая программа по биологии'));

        // Encrypted PDF check
        final encryptedPdf = Uint8List.fromList(
          latin1.encode('%PDF-1.4\n/Encrypt 12 0 R\n%%EOF'),
        );
        expect(
          () => TextExtractor.extract(
            bytes: encryptedPdf,
            format: DocumentFormat.pdf,
            fileName: 'secret.pdf',
          ),
          throwsA(
            predicate(
              (e) =>
                  e is DocumentProcessingException &&
                  e.code == 'password_protected',
            ),
          ),
        );

        // Scanned image PDF without text layer
        final scannedPdf = Uint8List.fromList(
          latin1.encode('%PDF-1.4\n/Type /Page\n/Image /Subtype /Image\n%%EOF'),
        );
        expect(
          () => TextExtractor.extract(
            bytes: scannedPdf,
            format: DocumentFormat.pdf,
            fileName: 'scan.pdf',
          ),
          throwsA(
            predicate(
              (e) =>
                  e is DocumentProcessingException &&
                  e.code == 'scanned_image_no_text',
            ),
          ),
        );
      },
    );
  });

  group('F12-05: Sentence-Window Chunking', () {
    test('Chunks text with stable windows, sentence boundaries and metadata', () {
      const chunker = SentenceWindowChunker(
        targetChunkSize: 100,
        overlapSize: 30,
      );
      const text =
          'Первое предложение в тексте. Второе предложение с важной информацией! Третье предложение о правилах? Четвёртое предложение завершает первый раздел.';

      final extracted = ExtractedDocumentText(
        fullText: text,
        pages: [text],
        totalCharacters: text.length,
      );

      final chunks = chunker.chunkDocument(
        extracted: extracted,
        documentId: 'doc_1',
        revisionId: 'rev_1',
        ownerId: 'owner_1',
        documentName: 'Памятка.txt',
      );

      expect(chunks.isNotEmpty, isTrue);
      for (final chunk in chunks) {
        expect(chunk.documentId, 'doc_1');
        expect(chunk.revisionId, 'rev_1');
        expect(chunk.documentName, 'Памятка.txt');
        expect(chunk.metadata['strategy'], 'v1.0-sentence-window');
        expect(chunk.chunkText.isNotEmpty, isTrue);
      }
      expect(chunks.first.chunkIndex, 0);
      if (chunks.length > 1) {
        expect(chunks[1].chunkIndex, 1);
      }
    });
  });

  group('F12-06 & F12-07: Local Hybrid Search Engine', () {
    test(
      'Relevant query scores above threshold, irrelevant query returns no relevant matches',
      () {
        const engine = LocalHybridSearchEngine(relevanceThreshold: 0.35);

        final chunk1 = KnowledgeChunk(
          id: 'c1',
          revisionId: 'r1',
          documentId: 'd1',
          documentName: 'Расписание.docx',
          ownerId: 'o1',
          chunkIndex: 0,
          chunkText:
              'Расписание уроков 7 «Б» класса. Понедельник: 1. Алгебра в кабинете 24, 2. Физика в кабинете 18.',
          embeddingVector: engine.embedText(
            'Расписание уроков 7 «Б» класса. Понедельник: 1. Алгебра в кабинете 24, 2. Физика в кабинете 18.',
          ),
        );

        final chunk2 = KnowledgeChunk(
          id: 'c2',
          revisionId: 'r1',
          documentId: 'd1',
          documentName: 'Расписание.docx',
          ownerId: 'o1',
          chunkIndex: 1,
          chunkText:
              'Вторник: 1. Русский язык, 2. Литература, 3. География, 4. Физкультура.',
          embeddingVector: engine.embedText(
            'Вторник: 1. Русский язык, 2. Литература, 3. География, 4. Физкультура.',
          ),
        );

        final chunks = [chunk1, chunk2];

        // 1. Relevant search
        final matchedResult = engine.search(
          query: 'В какой кабинет идти на физику в понедельник?',
          chunks: chunks,
        );
        expect(matchedResult.hasRelevantMatches, isTrue);
        expect(matchedResult.matches.first.chunk.id, 'c1');
        expect(matchedResult.matches.first.isAboveThreshold, isTrue);
        expect(matchedResult.matches.first.score, greaterThanOrEqualTo(0.35));

        // 2. Irrelevant search (hallucination prevention per F12-07)
        final missingResult = engine.search(
          query: 'Какая средняя температура на экваторе планеты Марс?',
          chunks: chunks,
        );
        expect(missingResult.hasRelevantMatches, isFalse);
        expect(missingResult.matchedChunkTexts.isEmpty, isTrue);
      },
    );
  });

  group('F12-02, F12-11, F12-12: Persistent Knowledge Repository & SQLite Storage', () {
    late Directory tempDir;
    late StorageDatabase database;
    late PersistentKnowledgeRepository knowledgeRepo;
    const testOwner = 'test_owner_f12';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'craftai_knowledge_test_',
      );
      final dbPath = p.join(tempDir.path, 'test_knowledge.db');
      database = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await database.open();

      await database.db.insert(StorageSchemaV1.tableWorkspaces, {
        'owner_id': testOwner,
        'installation_id': 'inst_1',
        'schema_version': 1,
        'workspace_epoch': 1,
        'created_at_utc': DateTime.now().toUtc().toIso8601String(),
        'updated_at_utc': DateTime.now().toUtc().toIso8601String(),
      });

      knowledgeRepo = PersistentKnowledgeRepository(
        database: database,
        baseStorageDir: tempDir.path,
      );
    });

    tearDown(() async {
      await database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'Imports document safely to workspace directory with SHA-256 deduplication (F12-02)',
      () async {
        final sampleBytes = Uint8List.fromList(
          utf8.encode(
            'Правила дежурства в школе. Преподаватель обязан проверить журнал.',
          ),
        );
        final doc1 = await knowledgeRepo.importDocument(
          ownerId: testOwner,
          fileName: 'Памятка_учителя.txt',
          bytes: sampleBytes,
          format: DocumentFormat.txt,
        );

        expect(doc1.id, startsWith('doc_'));
        expect(doc1.chunksCount, greaterThan(0));

        // Verify physical file was saved in appDir/workspaces/<ownerId>/knowledge/<docId>.<ext>
        final expectedFile = File(
          p.join(
            tempDir.path,
            'workspaces',
            testOwner,
            'knowledge',
            '${doc1.id}.txt',
          ),
        );
        expect(await expectedFile.exists(), isTrue);

        // Verify deduplication: importing same bytes returns existing doc without duplicating storage
        final doc2 = await knowledgeRepo.importDocument(
          ownerId: testOwner,
          fileName: 'Памятка_копия.txt',
          bytes: sampleBytes,
          format: DocumentFormat.txt,
        );
        expect(doc2.id, doc1.id);
        expect(doc2.contentHash, doc1.contentHash);

        final allDocs = await knowledgeRepo.getDocuments(testOwner);
        expect(allDocs.length, 1);
      },
    );

    test(
      'Toggle document excludes chunks from search without deleting (F12-11)',
      () async {
        final sampleBytes = Uint8List.fromList(
          utf8.encode(
            'Информация о расписании 7Б класса. Понедельник: Алгебра.',
          ),
        );
        final doc = await knowledgeRepo.importDocument(
          ownerId: testOwner,
          fileName: 'Расписание.txt',
          bytes: sampleBytes,
          format: DocumentFormat.txt,
        );

        // Initially enabled: search finds chunk
        var searchRes = await knowledgeRepo.searchKnowledge(
          ownerId: testOwner,
          query: 'Алгебра',
        );
        expect(searchRes.hasRelevantMatches, isTrue);

        // Disable document
        await knowledgeRepo.toggleDocumentEnabled(
          ownerId: testOwner,
          docId: doc.id,
          isEnabled: false,
        );

        // Search now excludes it
        searchRes = await knowledgeRepo.searchKnowledge(
          ownerId: testOwner,
          query: 'Алгебра',
        );
        expect(searchRes.hasRelevantMatches, isFalse);
        expect(searchRes.totalScannedChunks, 0);

        // Re-enable document
        await knowledgeRepo.toggleDocumentEnabled(
          ownerId: testOwner,
          docId: doc.id,
          isEnabled: true,
        );
        searchRes = await knowledgeRepo.searchKnowledge(
          ownerId: testOwner,
          query: 'Алгебра',
        );
        expect(searchRes.hasRelevantMatches, isTrue);
      },
    );

    test(
      'Delete physically purges binary file, revisions, and chunks (F12-12 & ADR-02)',
      () async {
        final sampleBytes = Uint8List.fromList(
          utf8.encode(
            'Лабораторная работа по биологии №3. Препарат кожицы лука.',
          ),
        );
        final doc = await knowledgeRepo.importDocument(
          ownerId: testOwner,
          fileName: 'Биология.txt',
          bytes: sampleBytes,
          format: DocumentFormat.txt,
        );

        final binaryFile = File(
          p.join(
            tempDir.path,
            'workspaces',
            testOwner,
            'knowledge',
            '${doc.id}.txt',
          ),
        );
        expect(await binaryFile.exists(), isTrue);

        // Check DB records exist
        var chunks = await knowledgeRepo.getChunksForOwner(
          testOwner,
          enabledOnly: false,
        );
        expect(chunks.isNotEmpty, isTrue);

        // Delete document
        await knowledgeRepo.deleteDocument(ownerId: testOwner, docId: doc.id);

        // Physical file must be deleted
        expect(await binaryFile.exists(), isFalse);

        // DB chunks, revisions, documents must be gone
        chunks = await knowledgeRepo.getChunksForOwner(
          testOwner,
          enabledOnly: false,
        );
        expect(chunks.isEmpty, isTrue);
        final remainingDocs = await knowledgeRepo.getDocuments(testOwner);
        expect(remainingDocs.isEmpty, isTrue);
      },
    );
  });

  group(
    'F12-09 & F12-10: Local RAG Context Assembly & Trace Retrieval Layer',
    () {
      test(
        'ContextAssembler and RequestTrace include only retrieved chunks, not full file',
        () {
          const assembler = ContextAssembler();
          final chunks = [
            'Понедельник 7Б: 1. Алгебра, 2. Физика.',
            'Лабораторная работа №3: Изучение кожицы лука.',
          ];

          final manifest = assembler.assemble(
            manifestId: 'manifest_rag_test',
            requestId: 'req_rag_1',
            category: 'standard',
            catalogRevision: '2026-03-31-01',
            contextWindow: 128000,
            activeInstruction: 'Ты — помощник учителя.',
            knowledgeChunks: chunks,
            conversationHistory: [],
            userPrompt: 'Во сколько физика в понедельник?',
          );

          expect(manifest.knowledgeChunks.length, 2);
          expect(
            manifest.messages.any(
              (m) =>
                  m['role'] == 'system' &&
                  m['content']!.contains('[Источник]: Понедельник 7Б'),
            ),
            isTrue,
          );

          // Build trace from execution
          final trace = RequestTrace.fromExecution(
            requestId: 'req_rag_1',
            ownerId: 'owner_1',
            conversationId: 'conv_1',
            modelCategory: 'standard',
            assistantVersion: 1,
            userPrompt: 'Во сколько физика в понедельник?',
            responseText: 'В понедельник вторым уроком физика в кабинете 18.',
            durationMs: 340,
            status: TraceStatus.completed,
            manifest: manifest,
          );

          // Retrieval layer must exist with LocationTag.onDevice
          final retrievalLayer = trace.layers.firstWhere(
            (l) => l.type == TraceLayerType.retrieval,
          );
          expect(retrievalLayer.location, LocationTag.onDevice);
          expect(retrievalLayer.contentSnippet, contains('Понедельник 7Б'));
          expect(retrievalLayer.tokenCount, greaterThan(0));
        },
      );
    },
  );

  group('F12-08 & F12-V01: S41 Knowledge Page & D03 Dialog UI', () {
    late Directory tempDir;
    late StorageDatabase database;
    late PersistentKnowledgeRepository knowledgeRepo;
    const testOwner = 'test_owner_s41';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('craftai_s41_test_');
      final dbPath = p.join(tempDir.path, 'test_s41.db');
      database = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await database.open();

      await database.db.insert(StorageSchemaV1.tableWorkspaces, {
        'owner_id': testOwner,
        'installation_id': 'inst_2',
        'schema_version': 1,
        'workspace_epoch': 1,
        'created_at_utc': DateTime.now().toUtc().toIso8601String(),
        'updated_at_utc': DateTime.now().toUtc().toIso8601String(),
      });

      knowledgeRepo = PersistentKnowledgeRepository(
        database: database,
        baseStorageDir: tempDir.path,
      );
    });

    tearDown(() async {
      await database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets(
      'Renders storage chips, document cards, search test and threshold fallback',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Import sample document inside runAsync (handles compute isolate)
        await tester.runAsync(() async {
          final sampleDocx = createMockDocxBytes(
            'Расписание уроков 7Б класса. Понедельник: 1. Алгебра, 2. Физика.',
          );
          await knowledgeRepo.importDocument(
            ownerId: testOwner,
            fileName: 'Расписание_7Б.docx',
            bytes: sampleDocx,
            format: DocumentFormat.docx,
          );
        });

        final container = ProviderContainer(
          overrides: [
            storageDatabaseProvider.overrideWithValue(database),
            knowledgeRepositoryProvider.overrideWithValue(knowledgeRepo),
          ],
        );
        addTearDown(container.dispose);

        await tester.runAsync(() async {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const MaterialApp(
                localizationsDelegates: [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: [Locale('ru')],
                home: KnowledgePage(ownerId: testOwner, isLearningMode: true),
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();

        // 1. Verify storage chips per F12-V01
        expect(find.text('На устройстве: индекс и файлы'), findsOneWidget);
        expect(find.text('В облако: только фрагменты'), findsOneWidget);

        // 2. Verify imported document card
        expect(find.text('Расписание_7Б.docx'), findsOneWidget);
        expect(find.text('DOCX'), findsWidgets);

        // 3. Test matching query
        await tester.enterText(
          find.byType(TextField).last,
          'Кабинет физики в понедельник',
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Найти и ответить'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();

        // Check results
        expect(find.text('Результат поиска'), findsOneWidget);
        expect(find.text('Ответ ассистента:'), findsOneWidget);

        // 4. Test missing query below threshold
        await tester.enterText(
          find.byType(TextField).last,
          'Какая погода на Марсе?',
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Найти и ответить'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();

        // Check explicit fallback per F12-07
        expect(find.text('Ответа в документах нет'), findsOneWidget);
      },
    );
  });
}
