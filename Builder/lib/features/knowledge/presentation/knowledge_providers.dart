import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_providers.dart';
import '../../trace/domain/request_trace.dart';
import '../../trace/trace_providers.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_repository.dart';
import '../domain/text_extractor.dart';
import '../infrastructure/persistent_knowledge_repository.dart';

final knowledgeRepositoryProvider = Provider<KnowledgeRepository>((ref) {
  final db = ref.watch(storageDatabaseProvider);
  if (db == null) {
    throw StateError('StorageDatabase is not initialized');
  }
  return PersistentKnowledgeRepository(database: db);
});

final knowledgeDocumentsProvider = FutureProvider.family<List<KnowledgeDocument>, String>((ref, ownerId) async {
  final repo = ref.watch(knowledgeRepositoryProvider);
  return repo.getDocuments(ownerId);
});

class KnowledgeState {
  final List<KnowledgeDocument> documents;
  final bool isLoading;
  final bool isImporting;
  final bool isSearching;
  final KnowledgeSearchResult? searchResult;
  final String? testQuery;
  final String? generatedAnswer;
  final RequestTrace? lastTrace;
  final String? errorMessage;

  const KnowledgeState({
    this.documents = const [],
    this.isLoading = false,
    this.isImporting = false,
    this.isSearching = false,
    this.searchResult,
    this.testQuery,
    this.generatedAnswer,
    this.lastTrace,
    this.errorMessage,
  });

  KnowledgeState copyWith({
    List<KnowledgeDocument>? documents,
    bool? isLoading,
    bool? isImporting,
    bool? isSearching,
    KnowledgeSearchResult? searchResult,
    bool clearSearchResult = false,
    String? testQuery,
    String? generatedAnswer,
    bool clearGeneratedAnswer = false,
    RequestTrace? lastTrace,
    bool clearLastTrace = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return KnowledgeState(
      documents: documents ?? this.documents,
      isLoading: isLoading ?? this.isLoading,
      isImporting: isImporting ?? this.isImporting,
      isSearching: isSearching ?? this.isSearching,
      searchResult: clearSearchResult ? null : (searchResult ?? this.searchResult),
      testQuery: testQuery ?? this.testQuery,
      generatedAnswer: clearGeneratedAnswer ? null : (generatedAnswer ?? this.generatedAnswer),
      lastTrace: clearLastTrace ? null : (lastTrace ?? this.lastTrace),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class KnowledgeNotifier extends Notifier<KnowledgeState> {
  KnowledgeNotifier(this.ownerId);
  final String ownerId;

  KnowledgeRepository get repository => ref.watch(knowledgeRepositoryProvider);

  @override
  KnowledgeState build() {
    final docsAsync = ref.watch(knowledgeDocumentsProvider(ownerId));
    final docs = docsAsync.asData?.value ?? const [];
    return KnowledgeState(
      documents: docs,
      isLoading: docsAsync.isLoading,
      errorMessage: docsAsync.hasError ? docsAsync.error.toString() : null,
    );
  }

  Future<void> loadDocuments() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final docs = await repository.getDocuments(ownerId);
      state = state.copyWith(documents: docs, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Не удалось загрузить документы: $e',
      );
    }
  }

  Future<KnowledgeDocument?> importDocument({
    required String fileName,
    required Uint8List bytes,
    required DocumentFormat format,
  }) async {
    state = state.copyWith(isImporting: true, clearError: true);
    try {
      final doc = await repository.importDocument(
        ownerId: ownerId,
        fileName: fileName,
        bytes: bytes,
        format: format,
      );
      final updatedDocs = await repository.getDocuments(ownerId);
      state = state.copyWith(
        documents: updatedDocs,
        isImporting: false,
      );
      // Invalidate future provider so dependent views refresh
      ref.invalidate(knowledgeDocumentsProvider(ownerId));
      return doc;
    } on DocumentProcessingException catch (e) {
      state = state.copyWith(
        isImporting: false,
        errorMessage: e.message,
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        isImporting: false,
        errorMessage: 'Ошибка обработки файла: $e',
      );
      return null;
    }
  }

  Future<void> toggleDocument({
    required String docId,
    required bool isEnabled,
  }) async {
    try {
      await repository.toggleDocumentEnabled(
        ownerId: ownerId,
        docId: docId,
        isEnabled: isEnabled,
      );
      final updatedDocs = await repository.getDocuments(ownerId);
      state = state.copyWith(documents: updatedDocs);
      ref.invalidate(knowledgeDocumentsProvider(ownerId));
    } catch (e) {
      state = state.copyWith(errorMessage: 'Ошибка изменения статуса: $e');
    }
  }

  Future<void> deleteDocument(String docId) async {
    try {
      await repository.deleteDocument(
        ownerId: ownerId,
        docId: docId,
      );
      final updatedDocs = await repository.getDocuments(ownerId);
      state = state.copyWith(documents: updatedDocs);
      ref.invalidate(knowledgeDocumentsProvider(ownerId));
    } catch (e) {
      state = state.copyWith(errorMessage: 'Ошибка удаления документа: $e');
    }
  }

  Future<KnowledgeSearchResult> search(String query, {double? threshold}) async {
    state = state.copyWith(isSearching: true, clearError: true);
    try {
      final result = await repository.searchKnowledge(
        ownerId: ownerId,
        query: query,
        threshold: threshold,
      );
      state = state.copyWith(
        searchResult: result,
        testQuery: query,
        isSearching: false,
      );
      return result;
    } catch (e) {
      state = state.copyWith(
        isSearching: false,
        errorMessage: 'Ошибка поиска: $e',
      );
      return KnowledgeSearchResult(
        query: query,
        matches: const [],
        hasRelevantMatches: false,
        totalScannedChunks: 0,
        searchDurationMs: 0,
      );
    }
  }

  Future<void> testQueryAndGenerateAnswer(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    state = state.copyWith(
      isSearching: true,
      testQuery: trimmed,
      clearGeneratedAnswer: true,
      clearLastTrace: true,
      clearError: true,
    );

    final result = await search(trimmed);

    final reqId = 'req_knowledge_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now().toUtc();

    if (!result.hasRelevantMatches) {
      // Explicit fallback per F12-07 / F12-08 (no hallucination)
      final answer = 'Ответа в документах нет. В подключенных базах знаний отсутствует релевантная информация по данному вопросу.';

      final trace = RequestTrace(
        requestId: reqId,
        ownerId: ownerId,
        conversationId: 'knowledge_test',
        modelCategory: 'standard',
        assistantVersion: 1,
        layers: [
          const TraceLayer(
            type: TraceLayerType.retrieval,
            title: '3 · Найдено в документах',
            contentSnippet: 'Совпадений выше порога релевантности (0.35) не найдено.',
            tokenCount: 0,
            location: LocationTag.onDevice,
            extraChip: 'на телефоне',
          ),
          TraceLayer(
            type: TraceLayerType.userPrompt,
            title: 'Вопрос пользователя',
            contentSnippet: trimmed,
            tokenCount: (trimmed.length / 3.5).ceil(),
            location: LocationTag.onDevice,
          ),
          TraceLayer(
            type: TraceLayerType.response,
            title: 'Ответ модели',
            contentSnippet: answer,
            tokenCount: (answer.length / 3.5).ceil(),
            location: LocationTag.craftAi,
          ),
        ],
        steps: [
          const TraceStep(
            stepIndex: 1,
            title: 'Локальный RAG-поиск',
            description: 'Поиск по векторному индексу на телефоне (ниже порога)',
            location: LocationTag.onDevice,
          ),
        ],
        usage: TraceUsage(
          promptTokens: (trimmed.length / 3.5).ceil(),
          completionTokens: (answer.length / 3.5).ceil(),
          totalTokens: ((trimmed.length + answer.length) / 3.5).ceil(),
          durationMs: result.searchDurationMs + 120,
          isServerReported: false,
        ),
        status: TraceStatus.completed,
        createdAtUtc: startTime,
      );

      final traceRepo = ref.read(traceRepositoryProvider);
      await traceRepo.saveTrace(trace);

      state = state.copyWith(
        isSearching: false,
        generatedAnswer: answer,
        lastTrace: trace,
      );
      return;
    }

    // Has relevant matches
    final topChunk = result.matches.firstWhere((m) => m.isAboveThreshold);
    final buffer = StringBuffer();
    buffer.writeln('На основе документа «${topChunk.chunk.documentName}» (стр. ${topChunk.chunk.pageNumber}):\n');
    buffer.writeln(topChunk.chunk.chunkText);

    final answer = buffer.toString().trim();
    final chunkSnippet = result.matchedChunkTexts.take(2).map((c) => '[Фрагмент]: $c').join('\n\n');
    final chunkTokens = (chunkSnippet.length / 3.5).ceil();

    final trace = RequestTrace(
      requestId: reqId,
      ownerId: ownerId,
      conversationId: 'knowledge_test',
      modelCategory: 'standard',
      assistantVersion: 1,
      layers: [
        TraceLayer(
          type: TraceLayerType.retrieval,
          title: '3 · Найдено в документах',
          contentSnippet: chunkSnippet,
          tokenCount: chunkTokens,
          location: LocationTag.onDevice,
          extraChip: 'фрагменты',
        ),
        TraceLayer(
          type: TraceLayerType.userPrompt,
          title: 'Вопрос пользователя',
          contentSnippet: trimmed,
          tokenCount: (trimmed.length / 3.5).ceil(),
          location: LocationTag.onDevice,
        ),
        TraceLayer(
          type: TraceLayerType.response,
          title: 'Ответ модели',
          contentSnippet: answer,
          tokenCount: (answer.length / 3.5).ceil(),
          location: LocationTag.craftAi,
        ),
      ],
      steps: [
        TraceStep(
          stepIndex: 1,
          title: 'Локальный RAG-поиск',
          description: 'Найдено ${result.matches.where((m) => m.isAboveThreshold).length} совпадений на устройстве (${result.searchDurationMs} мс)',
          location: LocationTag.onDevice,
        ),
        const TraceStep(
          stepIndex: 2,
          title: 'Генерация ответа',
          description: 'Ответ сформирован строго по найденным фрагментам',
          location: LocationTag.craftAi,
        ),
      ],
      usage: TraceUsage(
        promptTokens: chunkTokens + (trimmed.length / 3.5).ceil(),
        completionTokens: (answer.length / 3.5).ceil(),
        totalTokens: chunkTokens + ((trimmed.length + answer.length) / 3.5).ceil(),
        durationMs: result.searchDurationMs + 250,
        isServerReported: false,
      ),
      status: TraceStatus.completed,
      createdAtUtc: startTime,
    );

    final traceRepo = ref.read(traceRepositoryProvider);
    await traceRepo.saveTrace(trace);

    state = state.copyWith(
      isSearching: false,
      generatedAnswer: answer,
      lastTrace: trace,
    );
  }
}

final knowledgeControllerProvider =
    NotifierProvider.family<KnowledgeNotifier, KnowledgeState, String>(
  KnowledgeNotifier.new,
);
