/// Three operational AI model categories supported by CraftAI.
///
/// Designed with 3-segment relative comparative scales for:
/// - Quality (Качество): 1–3
/// - Speed (Скорость): 1–3
/// - Price / Cost (Стоимость): 1–3
///
/// Scales are informational benchmarks (справочные) and do not represent
/// guaranteed latency or quota limits (FR-RUN-04, F06-05, F06-V01).
enum ModelCategory {
  fast(
    id: 'fast',
    defaultModelId: 'google/gemini-2.5-flash',
    qualityRating: 1,
    speedRating: 3,
    priceRating: 1,
  ),
  standard(
    id: 'standard',
    defaultModelId: 'anthropic/claude-3.5-sonnet',
    qualityRating: 2,
    speedRating: 2,
    priceRating: 2,
  ),
  advanced(
    id: 'advanced',
    defaultModelId: 'openai/o3-mini',
    qualityRating: 3,
    speedRating: 1,
    priceRating: 3,
  );

  const ModelCategory({
    required this.id,
    required this.defaultModelId,
    required this.qualityRating,
    required this.speedRating,
    required this.priceRating,
  });

  final String id;
  final String defaultModelId;
  final int qualityRating;
  final int speedRating;
  final int priceRating;

  static ModelCategory fromString(String? value) {
    if (value == null) return ModelCategory.standard;
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'fast' => ModelCategory.fast,
      'standard' => ModelCategory.standard,
      'advanced' => ModelCategory.advanced,
      _ => ModelCategory.standard,
    };
  }
}
