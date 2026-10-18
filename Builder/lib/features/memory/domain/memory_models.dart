/// Source of the memory fact.
enum MemoryFactSource {
  /// Added manually by the teacher.
  manual('manual', 'Вручную'),

  /// Suggested by the model from a conversation and explicitly approved by the teacher.
  suggested('suggested', 'Из диалога');

  final String id;
  final String label;

  const MemoryFactSource(this.id, this.label);

  static MemoryFactSource fromId(String id) {
    return MemoryFactSource.values.firstWhere(
      (s) => s.id == id,
      orElse: () => MemoryFactSource.manual,
    );
  }
}

/// A persistent classroom or teacher fact saved in SQLite (F13-01, F13-06).
class MemoryFact {
  final String id;
  final String ownerId;
  final String factText;
  final MemoryFactSource source;
  final bool isEnabled;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  const MemoryFact({
    required this.id,
    required this.ownerId,
    required this.factText,
    required this.source,
    this.isEnabled = true,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  MemoryFact copyWith({
    String? id,
    String? ownerId,
    String? factText,
    MemoryFactSource? source,
    bool? isEnabled,
    DateTime? createdAtUtc,
    DateTime? updatedAtUtc,
  }) {
    return MemoryFact(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      factText: factText ?? this.factText,
      source: source ?? this.source,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'fact_text': factText,
      'source': source.id,
      'is_enabled': isEnabled ? 1 : 0,
      'created_at_utc': createdAtUtc.toIso8601String(),
      'updated_at_utc': updatedAtUtc.toIso8601String(),
    };
  }

  factory MemoryFact.fromMap(Map<String, dynamic> map) {
    return MemoryFact(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      factText: map['fact_text'] as String,
      source: MemoryFactSource.fromId(map['source'] as String? ?? 'manual'),
      isEnabled: (map['is_enabled'] as int? ?? 1) == 1,
      createdAtUtc: DateTime.tryParse(map['created_at_utc'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      updatedAtUtc: DateTime.tryParse(map['updated_at_utc'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}

/// Candidate fact proposed by assistant/model (F13-03).
///
/// NOTE: A proposed candidate fact is NOT saved into persistent memory
/// until explicitly confirmed and accepted by the teacher.
class MemoryCandidateFact {
  final String id;
  final String ownerId;
  final String factText;
  final String? rationale;
  final DateTime suggestedAtUtc;

  const MemoryCandidateFact({
    required this.id,
    required this.ownerId,
    required this.factText,
    this.rationale,
    required this.suggestedAtUtc,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'fact_text': factText,
      'rationale': rationale,
      'suggested_at_utc': suggestedAtUtc.toIso8601String(),
    };
  }

  factory MemoryCandidateFact.fromMap(Map<String, dynamic> map) {
    return MemoryCandidateFact(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      factText: map['fact_text'] as String,
      rationale: map['rationale'] as String?,
      suggestedAtUtc: DateTime.tryParse(map['suggested_at_utc'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}

/// Deterministic policy for selecting memory facts into LLM prompt budget (F13-04).
class MemorySelectionPolicy {
  /// Maximum token budget allocated to memory facts in system prompt.
  final int maxTokenBudget;

  const MemorySelectionPolicy({
    this.maxTokenBudget = 300,
  });

  /// Selects enabled facts in a deterministic canonical order (by created date ascending),
  /// trimming facts when the token budget is reached.
  List<MemoryFact> selectForContext(List<MemoryFact> allFacts) {
    final active = allFacts.where((f) => f.isEnabled).toList()
      ..sort((a, b) => a.createdAtUtc.compareTo(b.createdAtUtc));

    final selected = <MemoryFact>[];
    int currentTokens = 0;

    for (final fact in active) {
      final tokens = estimateTokens(fact.factText);
      if (currentTokens + tokens <= maxTokenBudget || selected.isEmpty) {
        selected.add(fact);
        currentTokens += tokens;
      } else {
        // Exceeded token budget
        break;
      }
    }

    return selected;
  }

  /// Approximate token estimator for Russian/English text (~3.5 chars per token).
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.trim().length / 3.5).ceil();
  }
}
