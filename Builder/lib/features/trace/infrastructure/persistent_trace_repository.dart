import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import '../domain/request_trace.dart';
import '../domain/trace_repository.dart';

class PersistentTraceRepository implements TraceRepository {
  final Database db;
  final String ownerId;
  final Map<String, RequestTrace> _ephemeralCache = {};

  PersistentTraceRepository({
    required this.db,
    required this.ownerId,
  });

  factory PersistentTraceRepository.fromStorage({
    required StorageDatabase storageDatabase,
    required String ownerId,
  }) {
    return PersistentTraceRepository(db: storageDatabase.db, ownerId: ownerId);
  }

  @override
  Future<RequestTrace?> getTrace(String requestId) async {
    if (_ephemeralCache.containsKey(requestId)) {
      return _ephemeralCache[requestId];
    }

    final rows = await db.query(
      StorageSchemaV1.tableRequestTraces,
      where: 'request_id = ? AND owner_id = ?',
      whereArgs: [requestId, ownerId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final contextLayersJson = row['context_layers_json'] as String;
    final payload = jsonDecode(contextLayersJson) as Map<String, dynamic>;
    return RequestTrace.fromJson(payload);
  }

  @override
  Future<void> saveTrace(RequestTrace trace, {bool isEphemeral = false}) async {
    if (isEphemeral) {
      _ephemeralCache[trace.requestId] = trace;
      return;
    }

    final payload = jsonEncode(trace.toJson());
    await db.insert(
      StorageSchemaV1.tableRequestTraces,
      {
        'request_id': trace.requestId,
        'owner_id': ownerId,
        'context_layers_json': payload,
        'sent_chunks_json': jsonEncode(trace.layers.map((l) => l.toJson()).toList()),
        'usage_json': jsonEncode(trace.usage.toJson()),
        'duration_ms': trace.usage.durationMs,
        'error_code': trace.errorCode,
        'created_at_utc': trace.createdAtUtc.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<RequestTrace> getSampleTrace({String? languageCode}) async {
    return createSampleFixture(languageCode: languageCode);
  }

  static RequestTrace createSampleFixture({String? languageCode}) {
    final isKk = languageCode?.toLowerCase() == 'kk';
    return RequestTrace(
      requestId: 'sample-trace-748',
      ownerId: 'sample-owner',
      conversationId: 'sample-conv',
      modelCategory: 'standard',
      assistantVersion: 3,
      layers: [
        TraceLayer(
          type: TraceLayerType.instruction,
          title: isKk ? '1 · Нұсқаулық v3' : '1 · Инструкция v3',
          contentSnippet: isKk
              ? 'Сіз — 7–8 сынып математика пәні мұғалімінің көмекшісісіз. Қысқа әрі түсінікті жауап беріңіз…'
              : 'Ты — помощник учителя математики 7–8 классов. Отвечай кратко, объясняй пошагово…',
          tokenCount: 180,
          location: LocationTag.onDevice,
          extraChip: isKk ? 'телефонда' : 'на телефоне',
        ),
        TraceLayer(
          type: TraceLayerType.memory,
          title: isKk ? '2 · Жад' : '2 · Память',
          contentSnippet: isKk
              ? 'Сыныпта 28 оқушы бар. Сабақ 45 минут.'
              : 'В классе 28 учеников. Урок 45 минут.',
          tokenCount: 24,
          location: LocationTag.onDevice,
          extraChip: isKk ? 'телефонда' : 'на телефоне',
        ),
        TraceLayer(
          type: TraceLayerType.retrieval,
          title: isKk ? '3 · Құжаттардан табылды' : '3 · Найдено в документах',
          contentSnippet: isKk
              ? '«Алгебра оқулығы.pdf», 84-бет: сызықтық теңдеу дегеніміз ax + b = 0 түріндегі…'
              : '«Учебник алгебры.pdf», с. 84: линейное уравнение — это уравнение вида ax + b = 0…',
          tokenCount: 310,
          location: LocationTag.onDevice,
          extraChip: isKk ? '2 үзінді' : '2 фрагмента',
        ),
        TraceLayer(
          type: TraceLayerType.userPrompt,
          title: isKk ? '4 · Сіздің сұрағыңыз' : '4 · Ваш вопрос',
          contentSnippet: isKk
              ? '«Сызықтық теңдеулер» тақырыбы бойынша 7-сыныпқа 4 тапсырмадан тұратын тексеру жұмысын құрастыр.'
              : 'Составь проверочную по теме «Линейные уравнения», 7 класс, 4 задания.',
          tokenCount: 22,
          location: LocationTag.onDevice,
          extraChip: isKk ? 'сіз' : 'вы',
        ),
        TraceLayer(
          type: TraceLayerType.response,
          title: isKk ? 'Жауап мәтіні' : 'Текст ответа',
          contentSnippet: isKk
              ? 'Тексеру жұмысы: сызықтық теңдеулер. 1. Есептеңіз: 3x + 7 = 22…'
              : 'Проверочная: линейные уравнения. 1. Решите: 3x + 7 = 22…',
          tokenCount: 212,
          location: LocationTag.abroad,
          extraChip: isKk ? 'шетелде' : 'за рубежом',
        ),
        TraceLayer(
          type: TraceLayerType.appAction,
          title: isKk ? 'Қосымша орындады' : 'Приложение сделало',
          contentSnippet: isKk
              ? 'Жауапты көрсетті және оны сөйлесу тарихында сақтады'
              : 'Показало ответ и сохранило его в истории',
          tokenCount: 0,
          location: LocationTag.onDevice,
        ),
      ],
      steps: [
        TraceStep(
          stepIndex: 1,
          title: isKk ? 'Сіз жаздыңыз' : 'Вы написали',
          description: isKk
              ? '«Сызықтық теңдеулер» тақырыбы бойынша 7-сыныпқа 4 тапсырмадан тұратын тексеру жұмысын құрастыр.'
              : '«Составь проверочную по теме «Линейные уравнения», 7 класс, 4 задания.»',
          location: LocationTag.onDevice,
          isCompleted: true,
        ),
        TraceStep(
          stepIndex: 2,
          title: isKk ? 'Қосымша сұранысты жинады' : 'Приложение собрало запрос',
          description: isKk
              ? 'Сұрағыңызға нұсқаулық, жадтағы деректер және құжаттардан табылған үзінділер қосылды.'
              : 'К вашему вопросу добавлены инструкция, факты из памяти и найденные фрагменты документов.',
          location: LocationTag.onDevice,
          isCompleted: true,
        ),
        TraceStep(
          stepIndex: 3,
          title: isKk ? 'CraftAI сервері' : 'Сервер CraftAI',
          description: isKk
              ? 'Есептік жазбаны тексеріп, сұранысты таңдалған модельге бағыттады.'
              : 'Проверил аккаунт и переслал запрос выбранной модели.',
          location: LocationTag.craftAi,
          isCompleted: true,
        ),
        TraceStep(
          stepIndex: 4,
          title: isKk ? '«Жұмыс» моделі' : 'Модель «Рабочая»',
          description: isKk
              ? 'Сұранысты толық оқып, жауапты біртіндеп жазды: 212 токен, 4,1 с.'
              : 'Читает весь запрос целиком и пишет ответ по слову: 212 токенов, 4,1 с.',
          location: LocationTag.abroad,
          isCompleted: true,
          durationMs: 4100,
        ),
        TraceStep(
          stepIndex: 5,
          title: isKk ? 'Телефондағы жауап' : 'Ответ на телефоне',
          description: isKk
              ? 'Қосымша мәтінді көрсетті және оны сөйлесу тарихында сақтады.'
              : 'Приложение показало текст и сохранило его в истории диалога.',
          location: LocationTag.onDevice,
          isCompleted: true,
        ),
      ],
      usage: const TraceUsage(
        promptTokens: 536,
        completionTokens: 212,
        totalTokens: 748,
        durationMs: 4600,
        isServerReported: true,
        costTier: 2,
      ),
      status: TraceStatus.completed,
      createdAtUtc: DateTime.utc(2026, 10, 17, 12, 0, 0),
      isExample: true,
    );
  }
}

class InMemoryTraceRepository implements TraceRepository {
  final Map<String, RequestTrace> _traces = {};

  @override
  Future<RequestTrace?> getTrace(String requestId) async {
    return _traces[requestId];
  }

  @override
  Future<void> saveTrace(RequestTrace trace) async {
    _traces[trace.requestId] = trace;
  }

  @override
  Future<RequestTrace> getSampleTrace({String? languageCode}) async {
    return PersistentTraceRepository.createSampleFixture(languageCode: languageCode);
  }
}
