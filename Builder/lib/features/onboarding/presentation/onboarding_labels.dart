import '../../../app/localization/app_localizations.dart';
import '../domain/assistant_setup.dart';

String subjectLabel(SchoolSubject subject, AppLocalizations s) =>
    switch (subject) {
      SchoolSubject.mathematics => s.subjectMathematics,
      SchoolSubject.russian => s.subjectRussian,
      SchoolSubject.kazakh => s.subjectKazakh,
      SchoolSubject.english => s.subjectEnglish,
      SchoolSubject.history => s.subjectHistory,
      SchoolSubject.biology => s.subjectBiology,
      SchoolSubject.geography => s.subjectGeography,
      SchoolSubject.physics => s.subjectPhysics,
      SchoolSubject.chemistry => s.subjectChemistry,
      SchoolSubject.informatics => s.subjectInformatics,
      SchoolSubject.primary => s.subjectPrimary,
      SchoolSubject.other => s.subjectOther,
    };

String setupSubject(AssistantSetup draft, AppLocalizations s) =>
    draft.subject == SchoolSubject.other &&
        draft.customSubject.trim().isNotEmpty
    ? draft.customSubject.trim()
    : draft.subject == null
    ? s.onbChooseSubject
    : subjectLabel(draft.subject!, s);

String languageLabel(AssistantLanguage language, AppLocalizations s) =>
    switch (language) {
      AssistantLanguage.russian => s.onbRussian,
      AssistantLanguage.kazakh => s.onbKazakh,
      AssistantLanguage.bilingual => s.onbBilingual,
    };
