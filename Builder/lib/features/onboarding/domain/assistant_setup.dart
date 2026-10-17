enum SchoolSubject {
  mathematics,
  russian,
  kazakh,
  english,
  history,
  biology,
  geography,
  physics,
  chemistry,
  informatics,
  primary,
  other,
}

enum AssistantLanguage { russian, kazakh, bilingual }

/// Local presentation settings. Never implicitly added to model context.
class AssistantSetup {
  AssistantSetup({
    this.subject,
    this.customSubject = '',
    Set<int> grades = const {},
    this.language = AssistantLanguage.russian,
    this.name = '',
    this.nameEdited = false,
  }) : grades = Set.unmodifiable(grades) {
    if (grades.any((grade) => grade < 1 || grade > 11)) {
      throw ArgumentError('Grades must be between 1 and 11.');
    }
  }
  final SchoolSubject? subject;
  final String customSubject;
  final Set<int> grades;
  final AssistantLanguage language;
  final String name;
  final bool nameEdited;

  bool get preferencesValid =>
      subject != null &&
      grades.isNotEmpty &&
      (subject != SchoolSubject.other || customSubject.trim().isNotEmpty);
  bool get ready => preferencesValid && name.trim().isNotEmpty;

  AssistantSetup copyWith({
    SchoolSubject? subject,
    String? customSubject,
    Set<int>? grades,
    AssistantLanguage? language,
    String? name,
    bool? nameEdited,
  }) => AssistantSetup(
    subject: subject ?? this.subject,
    customSubject: customSubject ?? this.customSubject,
    grades: grades ?? this.grades,
    language: language ?? this.language,
    name: name ?? this.name,
    nameEdited: nameEdited ?? this.nameEdited,
  );

  AssistantSetup normalized() =>
      copyWith(customSubject: customSubject.trim(), name: name.trim());
}
