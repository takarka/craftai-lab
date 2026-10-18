import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/features/course/course_providers.dart';
import 'package:builder/features/course/domain/course_catalog.dart';
import 'package:builder/features/course/domain/course_models.dart';
import 'package:builder/features/course/domain/course_sample_documents.dart';
import 'package:builder/features/course/presentation/course_page.dart';
import 'package:builder/features/course/presentation/course_strings.dart';
import 'package:builder/features/course/presentation/glossary_page.dart';
import 'package:builder/features/profile/presentation/profile_strings.dart';

void main() {
  group('F17: Localization and Content Validator (RU/KK)', () {
    test('Strict locale code standards: only "ru" and "kk" supported', () {
      final locales = AppLocalizations.supportedLocales;
      expect(locales.map((l) => l.languageCode), containsAll(['ru', 'kk']));
      expect(locales.length, 2);

      // Verify no invalid country code or locale code like kz or KZ
      for (final locale in locales) {
        expect(locale.languageCode.toLowerCase(), isNot('kz'));
        expect(locale.countryCode?.toLowerCase(), isNot('kz'));
      }
    });

    test(
      'CourseCatalog levels bilingual parity: identical IDs and counts (5 active, 4 comingSoon)',
      () {
        final ruLevels = CourseCatalog.levelsRu;
        final kkLevels = CourseCatalog.levelsKk;

        expect(ruLevels.length, 9);
        expect(kkLevels.length, 9);

        final ruIds = ruLevels.map((l) => l.id).toList();
        final kkIds = kkLevels.map((l) => l.id).toList();
        expect(ruIds, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
        expect(kkIds, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
        expect(ruIds, equals(kkIds));

        final activeRu = ruLevels
            .where((l) => !l.comingSoon)
            .map((l) => l.id)
            .toList();
        final activeKk = kkLevels
            .where((l) => !l.comingSoon)
            .map((l) => l.id)
            .toList();
        expect(activeRu, [1, 2, 3, 4, 5]);
        expect(activeKk, [1, 2, 3, 4, 5]);
      },
    );

    test(
      'CourseCatalog completeness: all required fields non-empty across RU & KK for active levels',
      () {
        final locales = {
          'ru': CourseCatalog.levelsRu,
          'kk': CourseCatalog.levelsKk,
        };

        locales.forEach((localeCode, levels) {
          for (final level in levels) {
            expect(level.id, inInclusiveRange(1, 9));
            expect(
              level.title.trim(),
              isNotEmpty,
              reason: '$localeCode level ${level.id} title',
            );
            expect(
              level.subtitle.trim(),
              isNotEmpty,
              reason: '$localeCode level ${level.id} subtitle',
            );
            expect(level.estimatedMinutes, greaterThan(0));

            if (!level.comingSoon) {
              // Idea step
              expect(
                level.ideaTitle.trim(),
                isNotEmpty,
                reason: '$localeCode level ${level.id} ideaTitle',
              );
              expect(
                level.ideaText.trim(),
                isNotEmpty,
                reason: '$localeCode level ${level.id} ideaText',
              );
              expect(
                level.ideaExampleTemplate.trim(),
                isNotEmpty,
                reason: '$localeCode level ${level.id} ideaExampleTemplate',
              );

              // Practice step
              expect(
                level.practiceTask.trim(),
                isNotEmpty,
                reason: '$localeCode level ${level.id} practiceTask',
              );
              expect(
                level.practiceDefaultInput.trim(),
                isNotEmpty,
                reason: '$localeCode level ${level.id} practiceDefaultInput',
              );
              expect(
                level.practiceExpectedAnswer.trim(),
                isNotEmpty,
                reason: '$localeCode level ${level.id} answer',
              );

              // Under the hood
              expect(
                level.underTheHoodConcept.trim(),
                isNotEmpty,
                reason: '$localeCode level ${level.id} concept',
              );
              expect(
                level.underTheHoodExplanation.trim(),
                isNotEmpty,
                reason: '$localeCode level ${level.id} explanation',
              );
              expect(level.underTheHoodLayers.length, greaterThanOrEqualTo(3));
              for (final layer in level.underTheHoodLayers) {
                expect(layer['layer']?.trim(), isNotEmpty);
                expect(layer['detail']?.trim(), isNotEmpty);
              }

              // Quiz
              expect(
                level.quizQuestions.length,
                3,
                reason:
                    '$localeCode level ${level.id} must have 3 quiz questions',
              );
              expect(level.quizPassThreshold, inInclusiveRange(0.5, 1.0));
              for (var i = 0; i < level.quizQuestions.length; i++) {
                final q = level.quizQuestions[i];
                expect(
                  q.question.trim(),
                  isNotEmpty,
                  reason: '$localeCode level ${level.id} q$i',
                );
                expect(q.options.length, greaterThanOrEqualTo(3));
                for (final opt in q.options) {
                  expect(opt.trim(), isNotEmpty);
                }
                expect(
                  q.correctIndex,
                  inInclusiveRange(0, q.options.length - 1),
                );
                expect(q.explanation.trim(), isNotEmpty);
              }
            }
          }
        });
      },
    );

    test(
      'CourseCatalog dynamic switching: getLevels and getLevel by locale',
      () {
        final ru = CourseCatalog.getLevels(locale: 'ru');
        final kk = CourseCatalog.getLevels(locale: 'kk');
        final fallback = CourseCatalog.getLevels(locale: 'en');

        expect(ru.first.title, 'Пустой ассистент');
        expect(kk.first.title, 'Бос ассистент');
        expect(fallback.first.title, 'Пустой ассистент');

        final level1Kk = CourseCatalog.getLevel(1, locale: 'kk');
        final level1Ru = CourseCatalog.getLevel(1, locale: 'ru');
        expect(level1Kk?.title, 'Бос ассистент');
        expect(level1Ru?.title, 'Пустой ассистент');

        // Backward compatibility getters
        expect(CourseCatalog.allLevels.length, 9);
        expect(CourseCatalog.levels.length, 9);
        expect(CourseCatalog.allLevels.first.title, 'Пустой ассистент');
      },
    );

    test('LessonStep localizedTitle supports both RU and KK', () {
      final ruTitles = LessonStep.values
          .map((s) => s.localizedTitle(false))
          .toList();
      final kkTitles = LessonStep.values
          .map((s) => s.localizedTitle(true))
          .toList();

      expect(ruTitles, ['Идея', 'Практика', 'Под капотом', 'Проверка', 'Итог']);
      expect(kkTitles, [
        'Идея',
        'Тәжірибе',
        'Ішкі құрылымы',
        'Тексеру',
        'Қорытынды',
      ]);
    });

    test(
      'CourseSampleDocuments fixtures: non-empty, bilingual, zero student PII',
      () {
        final curRu = CourseSampleDocuments.curriculumSchedule.contentRu;
        final curKk = CourseSampleDocuments.curriculumSchedule.contentKk;
        final critRu = CourseSampleDocuments.assessmentCriteria.contentRu;
        final critKk = CourseSampleDocuments.assessmentCriteria.contentKk;

        expect(curRu.trim(), isNotEmpty);
        expect(curKk.trim(), isNotEmpty);
        expect(critRu.trim(), isNotEmpty);
        expect(critKk.trim(), isNotEmpty);

        // Verify RU and KK contents are distinct
        expect(curRu, isNot(equals(curKk)));
        expect(critRu, isNot(equals(critKk)));

        // PII checks: no phone patterns, no 12-digit IINs, no personal numbers
        final allDocs = [curRu, curKk, critRu, critKk];
        final iinPattern = RegExp(r'\b\d{12}\b');
        final phonePattern = RegExp(r'\+7\s?\(?\d{3}\)?\s?\d{3}');

        for (final doc in allDocs) {
          expect(
            iinPattern.hasMatch(doc),
            isFalse,
            reason: 'Must not contain 12-digit IIN',
          );
          expect(
            phonePattern.hasMatch(doc),
            isFalse,
            reason: 'Must not contain phone numbers',
          );
        }

        // Evaluation query pairs
        final pairs = CourseSampleDocuments.queryPairs;
        expect(pairs.length, greaterThanOrEqualTo(4));

        for (final p in pairs) {
          expect(p.queryRu.trim(), isNotEmpty);
          expect(p.queryKk.trim(), isNotEmpty);
          expect(p.expectedKeywordRu.trim(), isNotEmpty);
          expect(p.expectedKeywordKk.trim(), isNotEmpty);
        }

        // Ensure at least one positive hit and one negative refusal query
        expect(pairs.any((p) => p.isHit == true), isTrue);
        expect(pairs.any((p) => p.isHit == false), isTrue);
      },
    );

    test(
      'GlossaryPage terms: authentic Kazakh translations for every term',
      () {
        final terms = GlossaryPage.terms;
        expect(terms.length, greaterThanOrEqualTo(10));

        for (final t in terms) {
          expect(t.term.trim(), isNotEmpty);
          expect(t.definition.trim(), isNotEmpty);
          expect(t.termKk, isNotNull, reason: 'Term "${t.id}" missing termKk');
          expect(t.termKk!.trim(), isNotEmpty);
          expect(
            t.definitionKk,
            isNotNull,
            reason: 'Term "${t.id}" missing definitionKk',
          );
          expect(t.definitionKk!.trim(), isNotEmpty);

          expect(t.localizedTerm(false), t.term);
          expect(t.localizedTerm(true), t.termKk);
          expect(t.localizedDefinition(false), t.definition);
          expect(t.localizedDefinition(true), t.definitionKk);
        }
      },
    );

    test('ProfileStrings FAQ bilingual parity', () {
      const ruStrings = ProfileStrings.withLocale(isKk: false);
      const kkStrings = ProfileStrings.withLocale(isKk: true);

      final ruFaq = ruStrings.faq;
      final kkFaq = kkStrings.faq;

      expect(ruFaq.length, kkFaq.length);
      expect(ruFaq.length, greaterThanOrEqualTo(5));

      for (var i = 0; i < ruFaq.length; i++) {
        expect(ruFaq[i].id, kkFaq[i].id);
        expect(ruFaq[i].question.trim(), isNotEmpty);
        expect(ruFaq[i].answer.trim(), isNotEmpty);
        expect(kkFaq[i].question.trim(), isNotEmpty);
        expect(kkFaq[i].answer.trim(), isNotEmpty);
        expect(ruFaq[i].question, isNot(equals(kkFaq[i].question)));
        expect(ruFaq[i].answer, isNot(equals(kkFaq[i].answer)));
      }
    });

    test('CourseStrings bilingual parity', () {
      const ru = CourseStrings.withLocale(isKk: false);
      const kk = CourseStrings.withLocale(isKk: true);

      expect(ru.levelsProgressTitle, 'Пять уровней мастерства');
      expect(kk.levelsProgressTitle, 'Шеберліктің бес деңгейі');

      expect(ru.levelPrefix(1), 'Уровень 1');
      expect(kk.levelPrefix(1), '1-деңгей');

      expect(ru.stepIndicator(1, 5, LessonStep.idea), 'Шаг 1 из 5 · Идея');
      expect(
        kk.stepIndicator(1, 5, LessonStep.idea),
        '5 қадамның 1-қадамы · Идея',
      );

      expect(ru.quizPassedTitle, 'Зачёт сдан!');
      expect(kk.quizPassedTitle, 'Сынақ тапсырылды!');

      expect(ru.previousStep, 'Назад');
      expect(kk.previousStep, 'Артқа');
    });

    Widget createTestApp({required String ownerId, required Locale locale}) {
      return ProviderScope(
        overrides: [
          overallCourseProgressProvider(ownerId).overrideWith(
            (ref) => const OverallCourseProgress(
              completedLevelsCount: 1,
              totalActiveLevels: 5,
              activeLevelId: 2,
              activeStep: LessonStep.idea,
            ),
          ),
          courseProgressListProvider(ownerId).overrideWith(
            (ref) => [
              LevelProgress(
                ownerId: ownerId,
                levelId: 1,
                contentVersion: '1.0.0',
                currentStep: 5,
                completedCheckpoints: const [1, 2, 3, 4, 5],
                attemptsCount: 1,
                isCompleted: true,
                updatedAtUtc: DateTime.utc(2026, 10, 18),
              ),
              LevelProgress(
                ownerId: ownerId,
                levelId: 2,
                contentVersion: '1.0.0',
                currentStep: 1,
                completedCheckpoints: const [],
                attemptsCount: 0,
                isCompleted: false,
                updatedAtUtc: DateTime.utc(2026, 10, 18),
              ),
              for (int i = 3; i <= 9; i++)
                LevelProgress(
                  ownerId: ownerId,
                  levelId: i,
                  contentVersion: '1.0.0',
                  currentStep: 1,
                  completedCheckpoints: const [],
                  attemptsCount: 0,
                  isCompleted: false,
                  updatedAtUtc: DateTime.utc(2026, 10, 18),
                ),
            ],
          ),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: CoursePage(ownerId: ownerId),
        ),
      );
    }

    testWidgets('CoursePage renders Kazakh titles when locale is "kk"', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestApp(ownerId: 'test_owner_kk', locale: const Locale('kk')),
      );
      await tester.pumpAndSettle();

      // Check Kazakh section header, level titles and badges
      expect(find.text('Оқу жолы'), findsOneWidget);
      expect(find.text('Бос ассистент'), findsOneWidget);
      expect(find.text('Нұсқаулықтар'), findsOneWidget);
      expect(find.text('1-деңгей'), findsOneWidget);
      expect(find.text('2-деңгей'), findsOneWidget);
      expect(find.text('5 деңгейдің 1 деңгейі аяқталды'), findsOneWidget);
    });

    testWidgets('CoursePage renders Russian titles when locale is "ru"', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestApp(ownerId: 'test_owner_ru', locale: const Locale('ru')),
      );
      await tester.pumpAndSettle();

      // Check Russian section header, level titles and badges
      expect(find.text('Учебный путь'), findsOneWidget);
      expect(find.text('Пустой ассистент'), findsOneWidget);
      expect(find.text('Инструкции'), findsOneWidget);
      expect(find.text('Уровень 1'), findsOneWidget);
      expect(find.text('Уровень 2'), findsOneWidget);
      expect(find.text('Пройдено 1 из 5 уровней'), findsOneWidget);
    });
  });
}
