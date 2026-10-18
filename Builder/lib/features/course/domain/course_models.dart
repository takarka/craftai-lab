import 'package:flutter/foundation.dart';
import '../../assistant/domain/assistant_config.dart';

enum LessonStep {
  idea(1, 'Идея'),
  practice(2, 'Практика'),
  underTheHood(3, 'Под капотом'),
  quiz(4, 'Проверка'),
  summary(5, 'Итог');

  const LessonStep(this.stepNumber, this.title);
  final int stepNumber;
  final String title;

  String localizedTitle(bool isKk) {
    if (isKk) {
      return switch (this) {
        LessonStep.idea => 'Идея',
        LessonStep.practice => 'Тәжірибе',
        LessonStep.underTheHood => 'Ішкі құрылымы',
        LessonStep.quiz => 'Тексеру',
        LessonStep.summary => 'Қорытынды',
      };
    }
    return title;
  }

  static LessonStep fromNumber(int num) {
    return LessonStep.values.firstWhere(
      (s) => s.stepNumber == num,
      orElse: () => LessonStep.idea,
    );
  }
}

enum LevelStatus { locked, available, inProgress, completed, comingSoon }

@immutable
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.hint,
  });

  final String id;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String? hint;

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    'options': options,
    'correct_index': correctIndex,
    'explanation': explanation,
    if (hint != null) 'hint': hint,
  };

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
    id: json['id'] as String,
    question: json['question'] as String,
    options: (json['options'] as List<dynamic>).cast<String>(),
    correctIndex: json['correct_index'] as int,
    explanation: json['explanation'] as String,
    hint: json['hint'] as String?,
  );
}

@immutable
class CourseLevel {
  const CourseLevel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.estimatedMinutes,
    this.targetSkillId,
    this.targetSkillName,
    this.comingSoon = false,
    required this.ideaTitle,
    required this.ideaText,
    required this.ideaExampleTemplate,
    required this.practiceTask,
    required this.practiceDefaultInput,
    required this.practiceExpectedAnswer,
    required this.underTheHoodConcept,
    required this.underTheHoodExplanation,
    required this.underTheHoodLayers,
    required this.quizQuestions,
    this.quizPassThreshold = 0.66,
  });

  final int id;

  /// Stable editorial identity. Numeric [id] remains the progress/checkpoint key.
  String get contentId => 'course.level.${id.toString().padLeft(2, '0')}';
  final String title;
  final String subtitle;
  final int estimatedMinutes;
  final AssistantSkillId? targetSkillId;
  final String? targetSkillName;
  final bool comingSoon;

  // S22: Идея
  final String ideaTitle;
  final String ideaText;
  final String ideaExampleTemplate;

  // S23: Практика
  final String practiceTask;
  final String practiceDefaultInput;
  final String practiceExpectedAnswer;

  // S24: Под капотом
  final String underTheHoodConcept;
  final String underTheHoodExplanation;
  final List<Map<String, String>> underTheHoodLayers;

  // S25: Проверка
  final List<QuizQuestion> quizQuestions;
  final double quizPassThreshold;
}

@immutable
class LevelProgress {
  const LevelProgress({
    required this.ownerId,
    required this.levelId,
    required this.contentVersion,
    required this.currentStep,
    required this.completedCheckpoints,
    required this.attemptsCount,
    required this.isCompleted,
    required this.updatedAtUtc,
    this.practiceEvidenceMet = false,
  });

  final String ownerId;
  final int levelId;
  final String contentVersion;
  final int currentStep;
  final List<int> completedCheckpoints;
  final int attemptsCount;
  final bool isCompleted;
  final DateTime updatedAtUtc;
  final bool practiceEvidenceMet;

  LevelStatus get status {
    if (levelId > 5) return LevelStatus.comingSoon;
    if (isCompleted) return LevelStatus.completed;
    if (currentStep > 1) return LevelStatus.inProgress;
    return LevelStatus.available;
  }

  LevelProgress copyWith({
    int? currentStep,
    List<int>? completedCheckpoints,
    int? attemptsCount,
    bool? isCompleted,
    DateTime? updatedAtUtc,
    bool? practiceEvidenceMet,
  }) {
    return LevelProgress(
      ownerId: ownerId,
      levelId: levelId,
      contentVersion: contentVersion,
      currentStep: currentStep ?? this.currentStep,
      completedCheckpoints: completedCheckpoints ?? this.completedCheckpoints,
      attemptsCount: attemptsCount ?? this.attemptsCount,
      isCompleted: isCompleted ?? this.isCompleted,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      practiceEvidenceMet: practiceEvidenceMet ?? this.practiceEvidenceMet,
    );
  }
}

@immutable
class OverallCourseProgress {
  const OverallCourseProgress({
    required this.completedLevelsCount,
    this.totalActiveLevels = 5,
    this.activeLevelId,
    this.activeStep = LessonStep.idea,
    this.completedLevelIds = const {},
  });

  final int completedLevelsCount;
  final int totalActiveLevels;
  final int? activeLevelId;
  final LessonStep activeStep;
  final Set<int> completedLevelIds;

  bool get isAllCompleted => completedLevelsCount >= totalActiveLevels;
  double get progressRatio => totalActiveLevels > 0
      ? (completedLevelsCount / totalActiveLevels).clamp(0.0, 1.0)
      : 0.0;
}
