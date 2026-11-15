class ModelDescriptor {
  const ModelDescriptor({
    required this.modelId,
    required this.available,
    required this.streaming,
    required this.tools,
    required this.languages,
    required this.contextWindow,
  });

  final String modelId;
  final bool available;
  final bool streaming;
  final bool tools;
  final List<String> languages;
  final int contextWindow;

  factory ModelDescriptor.fromJson(Map<String, dynamic> json) {
    final modelId =
        json['modelId'] as String? ?? json['ModelId'] as String? ?? '';
    final available =
        json['available'] as bool? ?? json['Available'] as bool? ?? true;
    final streaming =
        json['streaming'] as bool? ?? json['Streaming'] as bool? ?? true;
    final tools = json['tools'] as bool? ?? json['Tools'] as bool? ?? true;
    final langsRaw = json['languages'] ?? json['Languages'];
    final languages = langsRaw is List
        ? langsRaw.map((e) => e.toString()).toList()
        : ['ru', 'kk'];
    final contextWindow =
        json['contextWindow'] as int? ??
        json['ContextWindow'] as int? ??
        128000;

    return ModelDescriptor(
      modelId: modelId,
      available: available,
      streaming: streaming,
      tools: tools,
      languages: languages,
      contextWindow: contextWindow,
    );
  }

  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    'available': available,
    'streaming': streaming,
    'tools': tools,
    'languages': languages,
    'contextWindow': contextWindow,
  };
}

class ModelCatalog {
  const ModelCatalog({
    required this.revision,
    required this.models,
    required this.fetchedAtUtc,
  });

  final String revision;
  final List<ModelDescriptor> models;
  final DateTime fetchedAtUtc;

  ModelDescriptor? getModel(String modelId) {
    for (final m in models) {
      if (m.modelId == modelId) return m;
    }
    return models.isNotEmpty ? models.first : null;
  }

  factory ModelCatalog.fromJson(
    Map<String, dynamic> json, [
    DateTime? fetchedAt,
  ]) {
    final revision =
        json['revision'] as String? ?? json['Revision'] as String? ?? 'rev-1';
    final modelsRaw = json['models'] ?? json['Models'];
    final models = modelsRaw is List
        ? modelsRaw
              .map((e) => ModelDescriptor.fromJson(e as Map<String, dynamic>))
              .toList()
        : <ModelDescriptor>[];

    return ModelCatalog(
      revision: revision,
      models: models,
      fetchedAtUtc: fetchedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'revision': revision,
    'models': models.map((m) => m.toJson()).toList(),
    'fetchedAtUtc': fetchedAtUtc.toIso8601String(),
  };

  static ModelCatalog defaultCatalog() {
    return ModelCatalog(
      revision: 'rev-offline-default',
      models: const [
        ModelDescriptor(
          modelId: 'google/gemini-2.5-flash',
          available: true,
          streaming: true,
          tools: true,
          languages: ['ru', 'kk'],
          contextWindow: 128000,
        ),
        ModelDescriptor(
          modelId: 'qwen/qwen3-32b',
          available: true,
          streaming: true,
          tools: true,
          languages: ['ru', 'kk'],
          contextWindow: 128000,
        ),
      ],
      fetchedAtUtc: DateTime.now().toUtc(),
    );
  }
}
