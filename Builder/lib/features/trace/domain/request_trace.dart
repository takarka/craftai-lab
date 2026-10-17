import 'package:flutter/foundation.dart';

enum TraceLayerType {
  instruction,
  memory,
  retrieval,
  history,
  userPrompt,
  response,
  appAction,
}

enum LocationTag {
  onDevice,
  craftAi,
  abroad,
}

enum TraceStatus {
  completed,
  streaming,
  interrupted,
  error,
}

@immutable
class TraceLayer {
  final TraceLayerType type;
  final String title;
  final String contentSnippet;
  final int tokenCount;
  final LocationTag location;
  final String? extraChip;

  const TraceLayer({
    required this.type,
    required this.title,
    required this.contentSnippet,
    required this.tokenCount,
    required this.location,
    this.extraChip,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'title': title,
    'contentSnippet': contentSnippet,
    'tokenCount': tokenCount,
    'location': location.name,
    if (extraChip != null) 'extraChip': extraChip,
  };

  factory TraceLayer.fromJson(Map<String, dynamic> json) {
    return TraceLayer(
      type: TraceLayerType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TraceLayerType.instruction,
      ),
      title: json['title'] as String? ?? '',
      contentSnippet: json['contentSnippet'] as String? ?? '',
      tokenCount: json['tokenCount'] as int? ?? 0,
      location: LocationTag.values.firstWhere(
        (e) => e.name == json['location'],
        orElse: () => LocationTag.onDevice,
      ),
      extraChip: json['extraChip'] as String?,
    );
  }
}

@immutable
class TraceStep {
  final int stepIndex;
  final String title;
  final String description;
  final LocationTag location;
  final bool isCompleted;
  final int? durationMs;

  const TraceStep({
    required this.stepIndex,
    required this.title,
    required this.description,
    required this.location,
    this.isCompleted = true,
    this.durationMs,
  });

  Map<String, dynamic> toJson() => {
    'stepIndex': stepIndex,
    'title': title,
    'description': description,
    'location': location.name,
    'isCompleted': isCompleted,
    if (durationMs != null) 'durationMs': durationMs,
  };

  factory TraceStep.fromJson(Map<String, dynamic> json) {
    return TraceStep(
      stepIndex: json['stepIndex'] as int? ?? 1,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      location: LocationTag.values.firstWhere(
        (e) => e.name == json['location'],
        orElse: () => LocationTag.onDevice,
      ),
      isCompleted: json['isCompleted'] as bool? ?? true,
      durationMs: json['durationMs'] as int?,
    );
  }
}

@immutable
class TraceUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int durationMs;
  final bool isServerReported;
  final int costTier; // 1..3

  const TraceUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.durationMs,
    required this.isServerReported,
    this.costTier = 2,
  });

  Map<String, dynamic> toJson() => {
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'totalTokens': totalTokens,
    'durationMs': durationMs,
    'isServerReported': isServerReported,
    'costTier': costTier,
  };

  factory TraceUsage.fromJson(Map<String, dynamic> json) {
    final prompt = json['promptTokens'] as int? ?? 0;
    final completion = json['completionTokens'] as int? ?? 0;
    return TraceUsage(
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens: json['totalTokens'] as int? ?? (prompt + completion),
      durationMs: json['durationMs'] as int? ?? 0,
      isServerReported: json['isServerReported'] as bool? ?? false,
      costTier: json['costTier'] as int? ?? 2,
    );
  }
}

@immutable
class RequestTrace {
  final String requestId;
  final String ownerId;
  final String conversationId;
  final String modelCategory;
  final int assistantVersion;
  final List<TraceLayer> layers;
  final List<TraceStep> steps;
  final TraceUsage usage;
  final TraceStatus status;
  final String? errorCode;
  final DateTime createdAtUtc;
  final bool isExample;

  const RequestTrace({
    required this.requestId,
    required this.ownerId,
    required this.conversationId,
    required this.modelCategory,
    required this.assistantVersion,
    required this.layers,
    required this.steps,
    required this.usage,
    required this.status,
    this.errorCode,
    required this.createdAtUtc,
    this.isExample = false,
  });

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'ownerId': ownerId,
    'conversationId': conversationId,
    'modelCategory': modelCategory,
    'assistantVersion': assistantVersion,
    'layers': layers.map((e) => e.toJson()).toList(),
    'steps': steps.map((e) => e.toJson()).toList(),
    'usage': usage.toJson(),
    'status': status.name,
    if (errorCode != null) 'errorCode': errorCode,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'isExample': isExample,
  };

  factory RequestTrace.fromJson(Map<String, dynamic> json) {
    return RequestTrace(
      requestId: json['requestId'] as String,
      ownerId: json['ownerId'] as String? ?? '',
      conversationId: json['conversationId'] as String? ?? '',
      modelCategory: json['modelCategory'] as String? ?? 'standard',
      assistantVersion: json['assistantVersion'] as int? ?? 1,
      layers: (json['layers'] as List<dynamic>? ?? [])
          .map((e) => TraceLayer.fromJson(e as Map<String, dynamic>))
          .toList(),
      steps: (json['steps'] as List<dynamic>? ?? [])
          .map((e) => TraceStep.fromJson(e as Map<String, dynamic>))
          .toList(),
      usage: TraceUsage.fromJson(json['usage'] as Map<String, dynamic>? ?? {}),
      status: TraceStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => TraceStatus.completed,
      ),
      errorCode: json['errorCode'] as String?,
      createdAtUtc: DateTime.tryParse(json['createdAtUtc'] as String? ?? '') ?? DateTime.now().toUtc(),
      isExample: json['isExample'] as bool? ?? false,
    );
  }

  factory RequestTrace.fromExecution({
    required String requestId,
    required String ownerId,
    required String conversationId,
    required String modelCategory,
    required int assistantVersion,
    required String userPrompt,
    required String responseText,
    required int durationMs,
    required TraceStatus status,
    String? errorCode,
    DateTime? createdAtUtc,
    int? serverPromptTokens,
    int? serverCompletionTokens,
    int costTier = 2,
    String? instructionSnippet,
    int instructionTokens = 180,
    String? memorySnippet,
    int memoryTokens = 24,
    String? retrievalSnippet,
    int retrievalTokens = 0,
    int historyTokens = 0,
  }) {
    final now = createdAtUtc ?? DateTime.now().toUtc();
    final promptEst = instructionTokens + memoryTokens + retrievalTokens + historyTokens + (userPrompt.length ~/ 4);
    final compEst = (responseText.length ~/ 4);

    final finalPrompt = serverPromptTokens ?? promptEst;
    final finalComp = serverCompletionTokens ?? (compEst > 0 ? compEst : 1);
    final isServer = serverPromptTokens != null && serverCompletionTokens != null;

    final layers = <TraceLayer>[
      TraceLayer(
        type: TraceLayerType.instruction,
        title: '1 · Инструкция v$assistantVersion',
        contentSnippet: instructionSnippet ?? 'Ты — помощник учителя. Отвечай кратко, объясняй пошагово…',
        tokenCount: instructionTokens,
        location: LocationTag.onDevice,
        extraChip: 'на телефоне',
      ),
      if (memoryTokens > 0)
        TraceLayer(
          type: TraceLayerType.memory,
          title: '2 · Память',
          contentSnippet: memorySnippet ?? 'В классе 28 учеников. Урок 45 минут.',
          tokenCount: memoryTokens,
          location: LocationTag.onDevice,
          extraChip: 'на телефоне',
        ),
      if (retrievalTokens > 0)
        TraceLayer(
          type: TraceLayerType.retrieval,
          title: '3 · Найдено в документах',
          contentSnippet: retrievalSnippet ?? 'Фрагменты учебных материалов…',
          tokenCount: retrievalTokens,
          location: LocationTag.onDevice,
          extraChip: 'фрагменты',
        ),
      TraceLayer(
        type: TraceLayerType.userPrompt,
        title: '4 · Ваш вопрос',
        contentSnippet: userPrompt,
        tokenCount: userPrompt.length ~/ 4,
        location: LocationTag.onDevice,
        extraChip: 'вы',
      ),
      TraceLayer(
        type: TraceLayerType.response,
        title: 'Текст ответа',
        contentSnippet: responseText.isEmpty && errorCode != null ? 'Ошибка: $errorCode' : responseText,
        tokenCount: finalComp,
        location: LocationTag.abroad,
        extraChip: 'за рубежом',
      ),
      const TraceLayer(
        type: TraceLayerType.appAction,
        title: 'Приложение сделало',
        contentSnippet: 'Показало ответ и сохранило его в истории',
        tokenCount: 0,
        location: LocationTag.onDevice,
      ),
    ];

    final steps = <TraceStep>[
      TraceStep(
        stepIndex: 1,
        title: 'Вы написали',
        description: '«$userPrompt»',
        location: LocationTag.onDevice,
        isCompleted: true,
      ),
      TraceStep(
        stepIndex: 2,
        title: 'Приложение собрало запрос',
        description: 'К вашему вопросу добавлены инструкция, память и фрагменты.',
        location: LocationTag.onDevice,
        isCompleted: true,
      ),
      const TraceStep(
        stepIndex: 3,
        title: 'Сервер CraftAI',
        description: 'Проверил аккаунт и переслал запрос выбранной модели.',
        location: LocationTag.craftAi,
        isCompleted: true,
      ),
      TraceStep(
        stepIndex: 4,
        title: 'Модель «$modelCategory»',
        description: status == TraceStatus.error
            ? 'Сбой при обращении к модели: ${errorCode ?? 'Неизвестная ошибка'}'
            : (status == TraceStatus.interrupted
                ? 'Генерация прервана пользователем.'
                : 'Читает весь запрос целиком и пишет ответ: $finalComp токенов.'),
        location: LocationTag.abroad,
        isCompleted: status == TraceStatus.completed,
        durationMs: durationMs,
      ),
      TraceStep(
        stepIndex: 5,
        title: 'Ответ на телефоне',
        description: status == TraceStatus.error
            ? 'Приложение показало сообщение об ошибке.'
            : 'Приложение показало текст и сохранило его в истории диалога.',
        location: LocationTag.onDevice,
        isCompleted: status != TraceStatus.error,
      ),
    ];

    return RequestTrace(
      requestId: requestId,
      ownerId: ownerId,
      conversationId: conversationId,
      modelCategory: modelCategory,
      assistantVersion: assistantVersion,
      layers: layers,
      steps: steps,
      usage: TraceUsage(
        promptTokens: finalPrompt,
        completionTokens: finalComp,
        totalTokens: finalPrompt + finalComp,
        durationMs: durationMs,
        isServerReported: isServer,
        costTier: costTier,
      ),
      status: status,
      errorCode: errorCode,
      createdAtUtc: now,
      isExample: false,
    );
  }
}

