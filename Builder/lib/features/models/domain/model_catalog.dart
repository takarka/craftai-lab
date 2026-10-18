import 'model_category.dart';

class ModelDescriptor {
  const ModelDescriptor({
    required this.category,
    required this.modelId,
    required this.available,
    required this.streaming,
    required this.tools,
    required this.languages,
    required this.contextWindow,
  });

  final ModelCategory category;
  final String modelId;
  final bool available;
  final bool streaming;
  final bool tools;
  final List<String> languages;
  final int contextWindow;

  factory ModelDescriptor.fromJson(Map<String, dynamic> json) {
    final categoryStr =
        json['category'] as String? ?? json['Category'] as String?;
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
      category: ModelCategory.fromString(categoryStr),
      modelId: modelId,
      available: available,
      streaming: streaming,
      tools: tools,
      languages: languages,
      contextWindow: contextWindow,
    );
  }

  Map<String, dynamic> toJson() => {
    'category': category.id,
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

  ModelDescriptor getModel(ModelCategory category) {
    return models.firstWhere(
      (m) => m.category == category,
      orElse: () => ModelDescriptor(
        category: category,
        modelId: category.defaultModelId,
        available: true,
        streaming: true,
        tools: true,
        languages: const ['ru', 'kk'],
        contextWindow: 128000,
      ),
    );
  }

  bool isCategoryAvailable(ModelCategory category) {
    final descriptor = models.cast<ModelDescriptor?>().firstWhere(
      (m) => m?.category == category,
      orElse: () => null,
    );
    return descriptor?.available ?? false;
  }

  /// Suggests a reliable fallback alternative when the requested category is unavailable (F06-07).
  ModelCategory suggestAlternative(ModelCategory unavailable) {
    // If standard is available, it is the primary balanced recommendation
    if (unavailable != ModelCategory.standard &&
        isCategoryAvailable(ModelCategory.standard)) {
      return ModelCategory.standard;
    }
    // Otherwise try fast
    if (unavailable != ModelCategory.fast &&
        isCategoryAvailable(ModelCategory.fast)) {
      return ModelCategory.fast;
    }
    // Otherwise try advanced
    if (unavailable != ModelCategory.advanced &&
        isCategoryAvailable(ModelCategory.advanced)) {
      return ModelCategory.advanced;
    }
    return ModelCategory.standard;
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
      models: [
        for (final category in ModelCategory.values)
          ModelDescriptor(
            category: category,
            modelId: category.defaultModelId,
            available: true,
            streaming: true,
            tools: true,
            languages: const ['ru', 'kk'],
            contextWindow: 128000,
          ),
      ],
      fetchedAtUtc: DateTime.now().toUtc(),
    );
  }
}
