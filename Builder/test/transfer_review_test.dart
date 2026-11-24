import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/features/course/course_providers.dart';
import 'package:builder/features/course/domain/course_models.dart';
import 'package:builder/features/course/domain/transfer_review.dart';
import 'package:builder/features/course/infrastructure/in_memory_course_repository.dart';
import 'package:builder/features/course/infrastructure/transfer_review_store.dart';
import 'package:builder/features/course/presentation/lesson_access_gate.dart';
import 'package:builder/features/course/presentation/lesson_player_page.dart';
import 'package:builder/ui_kit/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const owner = 'teacher-capstone';
  const other = 'other-teacher';
  const store = TransferReviewStore();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('equal rubric totals can hide an improvement and a regression', () {
    const review = TransferReview(
      prompt: 'synthetic',
      firstAnswer: 'before',
      instructionChange: 'one rule',
      secondAnswer: 'after',
      first: {
        TransferCriterion.source: TransferVerdict.revise,
        TransferCriterion.accuracy: TransferVerdict.met,
        TransferCriterion.grade: TransferVerdict.met,
        TransferCriterion.format: TransferVerdict.met,
      },
      second: {
        TransferCriterion.source: TransferVerdict.met,
        TransferCriterion.accuracy: TransferVerdict.revise,
        TransferCriterion.grade: TransferVerdict.met,
        TransferCriterion.format: TransferVerdict.met,
      },
    );
    expect(review.change, TransferChange.mixed);
  });

  for (final locale in ['ru', 'kk']) {
    testWidgets(
      'capstone resumes after reload and accepts no improvement ($locale)',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1500);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        Widget app(InMemoryCourseRepository repo) => ProviderScope(
          overrides: [courseRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LessonAccessGate(
              ownerId: owner,
              levelId: 12,
              child: LessonPlayerPage(ownerId: owner, levelId: 12),
            ),
          ),
        );

        Finder keyed(String id) => find.byKey(Key(id));
        Future<void> press(String id) async {
          final target = keyed(id);
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

        Future<void> capture(String round, String text) async {
          await tester.ensureVisible(keyed('transfer.$round.input'));
          await tester.enterText(keyed('transfer.$round.input'), text);
          await tester.pumpAndSettle();
          await press('transfer.$round.save');
        }

        final initialRepo = InMemoryCourseRepository();
        await initialRepo.completeLevel(ownerId: owner, levelId: 5);
        await tester.pumpWidget(app(initialRepo));
        await tester.pumpAndSettle();
        await press('lesson.ideaProceedBtn');

        final proceed = keyed('lesson.practiceProceedBtn');
        expect(tester.widget<BuilderButton>(proceed).onPressed, isNull);
        expect(keyed('practice.applyBtn'), findsNothing);
        expect(keyed('practice.openAgentsForTransfer'), findsOneWidget);
        expect(
          find.text(locale == 'kk' ? 'Жауапты тексеру' : 'Проверить ответ'),
          findsOneWidget,
        );
        final prompt = tester
            .widget<SelectableText>(keyed('transfer.prompt'))
            .data;
        expect(prompt, contains('3/8'));
        expect(prompt, contains('5/8'));

        await capture('first', 'Compare the numerators.');
        for (final criterion in TransferCriterion.values) {
          await press('transfer.first.${criterion.name}.revise');
        }
        await capture('edit', 'Ask for two short separate hints.');
        expect(tester.widget<BuilderButton>(proceed).onPressed, isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        final restartedRepo = InMemoryCourseRepository();
        await tester.pumpWidget(app(restartedRepo));
        await tester.pumpAndSettle();
        expect(keyed('lesson.step.2'), findsOneWidget);
        expect(keyed('transfer.first.saved'), findsOneWidget);
        expect(keyed('transfer.edit.saved'), findsOneWidget);
        expect(
          tester.widget<SelectableText>(keyed('transfer.prompt')).data,
          prompt,
        );
        expect(
          tester
              .widget<ChoiceChip>(keyed('transfer.first.source.revise'))
              .selected,
          isTrue,
        );
        expect(tester.widget<BuilderButton>(proceed).onPressed, isNull);

        await capture('repeat', 'Compare the numerators.');
        for (final criterion in TransferCriterion.values) {
          await press('transfer.repeat.${criterion.name}.revise');
        }
        expect(
          find.text(
            locale == 'kk' ? 'Бағалар өзгерген жоқ.' : 'Оценки не изменились.',
          ),
          findsOneWidget,
        );
        expect(keyed('transfer.first.saved'), findsOneWidget);
        expect(keyed('transfer.repeat.saved'), findsOneWidget);

        final saved = await store.read(owner);
        expect(saved?.change, TransferChange.unchanged);
        expect(saved?.firstAnswer, saved?.secondAnswer);
        expect(await store.read(other), isNull);
        expect(tester.widget<BuilderButton>(proceed).onPressed, isNotNull);
        await press('lesson.practiceProceedBtn');
        expect(keyed('lesson.step.3'), findsOneWidget);
        expect(
          (await store.read(owner))?.step,
          LessonStep.underTheHood.stepNumber,
        );
        expect(
          (await restartedRepo.getLevelProgress(
            owner,
            12,
          ))?.practiceEvidenceMet,
          isTrue,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(app(InMemoryCourseRepository()));
        await tester.pumpAndSettle();
        expect(keyed('lesson.step.3'), findsOneWidget);
      },
    );
  }
}
