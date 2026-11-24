enum TransferCriterion { source, accuracy, grade, format }

enum TransferVerdict { met, revise }

enum TransferChange { improved, worse, mixed, unchanged }

/// The teacher's own assessment. No mark is inferred from the answer text.
final class TransferReview {
  const TransferReview({
    required this.prompt,
    this.firstAnswer = '',
    this.instructionChange = '',
    this.secondAnswer = '',
    this.first = const {},
    this.second = const {},
    this.step = 2,
    this.completed = false,
  });

  final String prompt;
  final String firstAnswer;
  final String instructionChange;
  final String secondAnswer;
  final Map<TransferCriterion, TransferVerdict> first;
  final Map<TransferCriterion, TransferVerdict> second;
  final int step;
  final bool completed;

  bool get firstReviewed => firstAnswer.isNotEmpty && _allMarked(first);
  bool get secondReviewed =>
      firstReviewed &&
      instructionChange.isNotEmpty &&
      secondAnswer.isNotEmpty &&
      _allMarked(second);

  static bool _allMarked(Map<TransferCriterion, TransferVerdict> marks) =>
      TransferCriterion.values.every(marks.containsKey);

  TransferChange? get change {
    if (!secondReviewed) return null;
    bool improved = false;
    bool worse = false;
    for (final criterion in TransferCriterion.values) {
      if (first[criterion] != second[criterion]) {
        if (second[criterion] == TransferVerdict.met) {
          improved = true;
        } else {
          worse = true;
        }
      }
    }
    if (improved && worse) return TransferChange.mixed;
    if (improved) return TransferChange.improved;
    if (worse) return TransferChange.worse;
    return TransferChange.unchanged;
  }

  TransferReview copyWith({
    String? firstAnswer,
    String? instructionChange,
    String? secondAnswer,
    Map<TransferCriterion, TransferVerdict>? first,
    Map<TransferCriterion, TransferVerdict>? second,
    int? step,
    bool? completed,
  }) {
    return TransferReview(
      prompt: prompt,
      firstAnswer: firstAnswer ?? this.firstAnswer,
      instructionChange: instructionChange ?? this.instructionChange,
      secondAnswer: secondAnswer ?? this.secondAnswer,
      first: Map.unmodifiable(first ?? this.first),
      second: Map.unmodifiable(second ?? this.second),
      step: step ?? this.step,
      completed: completed ?? this.completed,
    );
  }

  Map<String, Object?> toJson() => {
    'prompt': prompt,
    'first_answer': firstAnswer,
    'instruction_change': instructionChange,
    'second_answer': secondAnswer,
    'first': {
      for (final entry in first.entries) entry.key.name: entry.value.name,
    },
    'second': {
      for (final entry in second.entries) entry.key.name: entry.value.name,
    },
    'step': step,
    'completed': completed,
  };

  factory TransferReview.fromJson(Map<String, dynamic> json) {
    final step = json['step'];
    return TransferReview(
      prompt: json['prompt'] as String,
      firstAnswer: json['first_answer'] as String? ?? '',
      instructionChange: json['instruction_change'] as String? ?? '',
      secondAnswer: json['second_answer'] as String? ?? '',
      first: _marks(json['first']),
      second: _marks(json['second']),
      step: step is int && step >= 1 && step <= 5 ? step : 2,
      completed: json['completed'] == true,
    );
  }

  static Map<TransferCriterion, TransferVerdict> _marks(Object? raw) {
    if (raw is! Map<String, dynamic>) return const {};
    return Map.unmodifiable({
      for (final criterion in TransferCriterion.values)
        for (final verdict in TransferVerdict.values)
          if (raw[criterion.name] == verdict.name) criterion: verdict,
    });
  }
}
