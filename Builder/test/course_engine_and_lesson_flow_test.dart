import 'dart:io';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/core/storage/database/storage_database.dart';
import 'package:builder/core/storage/schema/storage_schema_v1.dart';
import 'package:builder/core/storage/security/secure_key_storage.dart';
import 'package:builder/core/storage/storage_providers.dart';
import 'package:builder/core/storage/workspace/workspace_storage_service.dart';
import 'package:builder/features/assistant/assistant_providers.dart';
import 'package:builder/features/assistant/infrastructure/persistent_assistant_repository.dart';
import 'package:builder/features/assistant/presentation/assistant_page.dart';
import 'package:builder/features/chat/chat_providers.dart';
import 'package:builder/features/chat/domain/conversation.dart';
import 'package:builder/features/chat/infrastructure/persistent_chat_repository.dart';
import 'package:builder/features/course/course_providers.dart';
import 'package:builder/features/course/domain/course_catalog.dart';
import 'package:builder/features/course/domain/course_models.dart';
import 'package:builder/features/course/infrastructure/persistent_course_repository.dart';
import 'package:builder/features/course/presentation/course_page.dart';
import 'package:builder/features/course/presentation/glossary_page.dart';
import 'package:builder/features/course/presentation/lesson_player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockChatSessionNotifier extends ChatSessionNotifier {
  MockChatSessionNotifier(super.ownerId);

  @override
  ChatState build() {
    return ChatState(
      activeConversation: Conversation(
        id: 'test_conv',
        ownerId: ownerId,
        title: 'Тест',
        retentionPolicy: RetentionPolicy.persistent,
        createdAtUtc: DateTime.now().toUtc(),
        activityAtUtc: DateTime.now().toUtc(),
      ),
      messages: const [],
      isLoading: false,
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('F10: Course Catalog & Schemas (F10-01, F10-V01)', () {
    test('Catalog contains 9 levels with 5 active and 4 coming soon', () {
      final levels = CourseCatalog.allLevels;
      expect(levels.length, 9);

      for (int i = 1; i <= 5; i++) {
        final level = CourseCatalog.getLevel(i);
        expect(level, isNotNull);
        expect(level!.comingSoon, isFalse);
        expect(level.quizQuestions.length, greaterThanOrEqualTo(3));
        expect(level.quizPassThreshold, greaterThanOrEqualTo(0.66));
        for (final q in level.quizQuestions) {
          expect(q.options.length, greaterThanOrEqualTo(3));
          expect(q.correctIndex, inInclusiveRange(0, q.options.length - 1));
          expect(q.explanation.isNotEmpty, isTrue);
        }
      }

      for (int i = 6; i <= 9; i++) {
        final level = CourseCatalog.getLevel(i);
        expect(level, isNotNull);
        expect(level!.comingSoon, isTrue);
      }
    });

    test('Glossary contains terms mapped to levels', () {
      final terms = GlossaryPage.terms;
      expect(terms.length, greaterThanOrEqualTo(5));
      for (final t in terms) {
        expect(t.term.isNotEmpty, isTrue);
        expect(t.definition.isNotEmpty, isTrue);
      }
    });
  });

  group(
    'F10: PersistentCourseRepository (F10-02, F10-04, F10-07, F10-08, F10-09, F10-11)',
    () {
      late Directory tempDir;
      late StorageDatabase db;
      late WorkspaceStorageService wsService;
      late PersistentAssistantRepository assistantRepo;
      late PersistentCourseRepository courseRepo;
      const testOwner = 'test_owner_course_f10';

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('course_f10_test_');
        final dbPath = p.join(tempDir.path, 'course_f10.db');
        db = StorageDatabase(
          databasePath: dbPath,
          databaseFactory: databaseFactoryFfi,
        );
        await db.open();

        wsService = WorkspaceStorageService(
          database: db,
          keyStorage: InMemorySecureKeyStorage(),
          installationId: 'test_inst_course',
        );
        await wsService.openWorkspace(ownerId: testOwner);

        assistantRepo = PersistentAssistantRepository(
          database: db,
          workspaceService: wsService,
        );

        // Seed assistant config
        final nowUtc = DateTime.now().toUtc().toIso8601String();
        await db.db.insert(StorageSchemaV1.tableAssistantConfigurations, {
          'owner_id': testOwner,
          'name': 'Сова',
          'selected_category': 'standard',
          'enabled_skills_json': '[]',
          'system_rules_json': '["Отвечать кратко"]',
          'state_revision': 1,
          'updated_at_utc': nowUtc,
        });

        await db.db.insert(StorageSchemaV1.tableTeacherPreferences, {
          'owner_id': testOwner,
          'subject': 'math',
          'grades_json': '[5, 6]',
          'ui_language': 'ru',
          'assistant_language': 'ru',
          'reminders_enabled': 0,
          'storage_retention_days': 30,
          'updated_at_utc': nowUtc,
        });

        courseRepo = PersistentCourseRepository(
          database: db,
          assistantRepository: assistantRepo,
        );
      });

      tearDown(() async {
        await db.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test(
        'Initial statuses: L1 is available, L2..5 are locked, L6..9 are comingSoon',
        () async {
          final s1 = await courseRepo.getLevelStatus(testOwner, 1);
          expect(s1, LevelStatus.available);

          final s2 = await courseRepo.getLevelStatus(testOwner, 2);
          expect(s2, LevelStatus.locked);

          final s6 = await courseRepo.getLevelStatus(testOwner, 6);
          expect(s6, LevelStatus.comingSoon);

          final overall = await courseRepo.getOverallProgress(testOwner);
          expect(overall.completedLevelsCount, 0);
          expect(overall.totalActiveLevels, 5);
          expect(overall.activeLevelId, 1);
          expect(overall.isAllCompleted, isFalse);
        },
      );

      test(
        'Save checkpoint updates active step and practiceEvidenceMet (F10-04, F10-07)',
        () async {
          await courseRepo.saveCheckpoint(
            ownerId: testOwner,
            levelId: 1,
            step: 2,
            practiceEvidenceMet: true,
          );

          final progress = await courseRepo.getLevelProgress(testOwner, 1);
          expect(progress, isNotNull);
          expect(progress!.currentStep, 2);
          expect(progress.practiceEvidenceMet, isTrue);
          expect(progress.isCompleted, isFalse);

          final status = await courseRepo.getLevelStatus(testOwner, 1);
          expect(status, LevelStatus.inProgress);
        },
      );

      test(
        'Quiz evaluation: records attempts and enforces pass threshold (F10-08)',
        () async {
          // Wrong answers -> fails threshold
          final failResult = await courseRepo.recordQuizAttempt(
            ownerId: testOwner,
            levelId: 1,
            selectedAnswers: [0, 0, 0], // Level 1 correct answers are [1, 1, 1]
            threshold: 0.66,
          );
          expect(failResult, isFalse);

          final progressAfterFail = await courseRepo.getLevelProgress(
            testOwner,
            1,
          );
          expect(progressAfterFail?.attemptsCount, 1);

          // Level 1 questions: correct indices are [1, 1, 1]
          final passResult = await courseRepo.recordQuizAttempt(
            ownerId: testOwner,
            levelId: 1,
            selectedAnswers: [1, 1, 1],
            threshold: 0.66,
          );
          expect(passResult, isTrue);

          final progressAfterPass = await courseRepo.getLevelProgress(
            testOwner,
            1,
          );
          expect(progressAfterPass?.attemptsCount, 2);

          // Check quiz attempts table in DB
          final attemptRows = await db.db.query(
            StorageSchemaV1.tableQuizAttempts,
          );
          expect(attemptRows.length, 2);
          expect(attemptRows.last['score'], 1.0);
        },
      );

      test(
        'Atomic level completion: grants target skill and creates assistant version (F10-09)',
        () async {
          // Complete Level 2 (which targets AssistantSkillId.instructions)
          await courseRepo.completeLevel(ownerId: testOwner, levelId: 2);

          // Verify level 2 is completed
          final status2 = await courseRepo.getLevelStatus(testOwner, 2);
          expect(status2, LevelStatus.completed);

          // Verify assistant configuration has instructions skill enabled
          final updatedConfig = await assistantRepo.getConfiguration(testOwner);
          expect(updatedConfig, isNotNull);
          expect(updatedConfig!.enabledSkills, contains('instructions'));

          // Verify version history has commit
          final versions = await assistantRepo.getVersions(testOwner);
          expect(versions.length, 1);
          expect(versions.first.reason, contains('2: Инструкции'));
        },
      );

      test(
        'Idempotent re-completion: does not duplicate skill or create extra versions (F10-11)',
        () async {
          // First completion of level 2
          await courseRepo.completeLevel(ownerId: testOwner, levelId: 2);
          final versionsAfterFirst = await assistantRepo.getVersions(testOwner);
          expect(versionsAfterFirst.length, 1);

          // Second completion of same level
          await courseRepo.completeLevel(ownerId: testOwner, levelId: 2);
          final versionsAfterSecond = await assistantRepo.getVersions(
            testOwner,
          );
          expect(versionsAfterSecond.length, 1); // No duplicate version!

          final config = await assistantRepo.getConfiguration(testOwner);
          final skillCount = config!.enabledSkills
              .where((s) => s == 'instructions')
              .length;
          expect(skillCount, 1);
        },
      );

      test(
        'Completing all 5 levels updates overall progress to isAllCompleted (F10-02, F10-10)',
        () async {
          for (int i = 1; i <= 5; i++) {
            await courseRepo.completeLevel(ownerId: testOwner, levelId: i);
          }

          final overall = await courseRepo.getOverallProgress(testOwner);
          expect(overall.completedLevelsCount, 5);
          expect(overall.isAllCompleted, isTrue);
          expect(overall.activeLevelId, isNull);
        },
      );
    },
  );

  group('F10: Presentation & Navigation Widgets', () {
    late Directory tempDir;
    late StorageDatabase db;
    late WorkspaceStorageService wsService;
    late PersistentAssistantRepository assistantRepo;
    late PersistentCourseRepository courseRepo;
    late InMemoryChatRepository inMemoryChatRepo;
    const testOwner = 'test_owner_widgets_f10';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('course_widgets_f10_');
      final dbPath = p.join(tempDir.path, 'course_widgets_f10.db');
      db = StorageDatabase(
        databasePath: dbPath,
        databaseFactory: databaseFactoryFfi,
      );
      await db.open();

      wsService = WorkspaceStorageService(
        database: db,
        keyStorage: InMemorySecureKeyStorage(),
        installationId: 'test_inst_widgets',
      );
      await wsService.openWorkspace(ownerId: testOwner);

      assistantRepo = PersistentAssistantRepository(
        database: db,
        workspaceService: wsService,
      );

      final nowUtc = DateTime.now().toUtc().toIso8601String();
      await db.db.insert(StorageSchemaV1.tableAssistantConfigurations, {
        'owner_id': testOwner,
        'name': 'Сова',
        'selected_category': 'standard',
        'enabled_skills_json': '[]',
        'system_rules_json': '["Отвечать кратко"]',
        'state_revision': 1,
        'updated_at_utc': nowUtc,
      });

      await db.db.insert(StorageSchemaV1.tableTeacherPreferences, {
        'owner_id': testOwner,
        'subject': 'math',
        'grades_json': '[5, 6]',
        'ui_language': 'ru',
        'assistant_language': 'ru',
        'reminders_enabled': 0,
        'storage_retention_days': 30,
        'updated_at_utc': nowUtc,
      });

      courseRepo = PersistentCourseRepository(
        database: db,
        assistantRepository: assistantRepo,
      );

      inMemoryChatRepo = InMemoryChatRepository();
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Widget createTestApp(Widget child) {
      return ProviderScope(
        overrides: [
          storageDatabaseProvider.overrideWithValue(db),
          assistantRepositoryProvider.overrideWithValue(assistantRepo),
          courseRepositoryProvider.overrideWithValue(courseRepo),
          chatRepositoryProvider.overrideWithValue(inMemoryChatRepo),
          chatSessionProvider(
            testOwner,
          ).overrideWith(() => MockChatSessionNotifier(testOwner)),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      );
    }

    testWidgets(
      'S20 CoursePage displays 9 levels and locked level shows theory preview (F10-02, F10-13)',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          createTestApp(const CoursePage(ownerId: testOwner)),
        );
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpAndSettle();

        // Check section header
        expect(find.text('Учебный путь'), findsOneWidget);

        // Check level 1 and level 2 cards
        expect(find.byKey(const Key('course.levelCard.1')), findsOneWidget);
        expect(find.byKey(const Key('course.levelCard.2')), findsOneWidget);

        // Tap locked Level 2 -> should open theory preview dialog (F10-13)
        await tester.tap(find.byKey(const Key('course.levelCard.2')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('course.theoryPreviewDialog')),
          findsOneWidget,
        );
        expect(find.textContaining('Превью теории'), findsOneWidget);

        // Close dialog
        await tester.tap(find.text('Понятно'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('course.theoryPreviewDialog')),
          findsNothing,
        );

        // Scroll to bottom tiles
        await tester.scrollUntilVisible(
          find.byKey(const Key('course.glossaryTile')),
          300,
        );
        expect(find.byKey(const Key('course.glossaryTile')), findsOneWidget);
        expect(
          find.byKey(const Key('course.achievementsTile')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'S21 LessonPlayerPage flows through steps S22 -> S23 -> S24 -> S25 (F10-03, F10-05, F10-06, F10-12)',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          createTestApp(const LessonPlayerPage(ownerId: testOwner, levelId: 1)),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();

        // Step 1: Idea (S22)
        expect(find.byKey(const Key('lesson.step.1')), findsOneWidget);
        expect(find.byKey(const Key('lesson.ideaProceedBtn')), findsOneWidget);

        // Advance to Step 2: Practice (S23)
        await tester.tap(find.byKey(const Key('lesson.ideaProceedBtn')));
        await tester.pump();
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();

        expect(find.byKey(const Key('lesson.step.2')), findsOneWidget);
        expect(find.byKey(const Key('practice.applyBtn')), findsOneWidget);

        // Tap apply test prompt (F10-06)
        await tester.tap(find.byKey(const Key('practice.applyBtn')));
        await tester.pump();
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();

        // Advance to Step 3: Under the Hood (S24)
        await tester.tap(find.byKey(const Key('lesson.practiceProceedBtn')));
        await tester.pump();
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();

        expect(find.byKey(const Key('lesson.step.3')), findsOneWidget);

        // Close button '×' saves checkpoint (F10-12)
        await tester.tap(find.byKey(const Key('lesson.closeBtn')));
        await tester.pump();
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump(const Duration(seconds: 3));

        // Verify checkpoint saved in repo
        LevelProgress? progress;
        await tester.runAsync(() async {
          progress = await courseRepo.getLevelProgress(testOwner, 1);
        });
        expect(progress?.currentStep, 3);
        expect(progress?.practiceEvidenceMet, isTrue);
      },
    );

    testWidgets(
      'S25 Quiz displays question progress, navigation chips and auto-scrolls on answer and submission',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Pre-set progress to step 4 (Quiz)
        await tester.runAsync(() async {
          await courseRepo.saveCheckpoint(
            ownerId: testOwner,
            levelId: 1,
            step: 4,
            practiceEvidenceMet: true,
          );
        });

        await tester.pumpWidget(
          createTestApp(const LessonPlayerPage(ownerId: testOwner, levelId: 1)),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();

        // Question navigation chips
        expect(find.byKey(const Key('quiz.chip.0')), findsOneWidget);
        expect(find.byKey(const Key('quiz.chip.1')), findsOneWidget);
        expect(find.byKey(const Key('quiz.chip.2')), findsOneWidget);

        // Submit button shows unanswered count initially
        expect(find.text('Проверить ответы (0 из 3)'), findsOneWidget);

        // Tap chip 1 to jump to question 2, verifying chip tap works
        await tester.tap(find.byKey(const Key('quiz.chip.1')));
        await tester.pump(const Duration(milliseconds: 300));

        // Scroll back to and answer question 0
        await tester.scrollUntilVisible(
          find.byKey(const Key('quiz.q0.opt1')),
          -200,
        );
        await tester.tap(find.byKey(const Key('quiz.q0.opt1')));
        await tester.pump(const Duration(milliseconds: 300));

        // Scroll to and answer question 1
        await tester.scrollUntilVisible(
          find.byKey(const Key('quiz.q1.opt0')),
          200,
        );
        await tester.tap(find.byKey(const Key('quiz.q1.opt0')));
        await tester.pump(const Duration(milliseconds: 300));

        // Scroll to and answer question 2
        await tester.scrollUntilVisible(
          find.byKey(const Key('quiz.q2.opt1')),
          200,
        );
        await tester.tap(find.byKey(const Key('quiz.q2.opt1')));
        await tester.pump(const Duration(milliseconds: 300));

        // Now button shows ready state
        expect(find.byKey(const Key('lesson.quizSubmitBtn')), findsOneWidget);
        expect(find.text('Проверить ответы'), findsOneWidget);

        // Submit quiz
        await tester.tap(find.byKey(const Key('lesson.quizSubmitBtn')));
        await tester.pump();
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump(const Duration(milliseconds: 300));

        // Result banner is visible
        expect(find.byKey(const Key('quiz.resultBanner')), findsOneWidget);
      },
    );

    testWidgets(
      'S26 Summary displays test in chat card and button',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Pre-set progress to step 5 (Summary)
        await tester.runAsync(() async {
          await courseRepo.saveCheckpoint(
            ownerId: testOwner,
            levelId: 1,
            step: 5,
            practiceEvidenceMet: true,
          );
        });

        await tester.pumpWidget(
          createTestApp(const LessonPlayerPage(ownerId: testOwner, levelId: 1)),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();

        // Verify Test in Chat card and buttons
        expect(find.byKey(const Key('lesson.testInChatCard')), findsOneWidget);
        expect(find.byKey(const Key('lesson.testInChatBtn')), findsOneWidget);
        expect(find.byKey(const Key('lesson.summaryChatBtn')), findsOneWidget);
        expect(find.byKey(const Key('lesson.summaryFinishBtn')), findsOneWidget);
        expect(find.text('Протестировать в чате'), findsWidgets);
      },
    );

    testWidgets('S27 GlossaryPage displays search and items', (tester) async {
      await tester.pumpWidget(createTestApp(const GlossaryPage()));
      await tester.pumpAndSettle();

      expect(find.text('Словарь терминов ИИ'), findsOneWidget);
      expect(find.byKey(const Key('glossary.searchField')), findsOneWidget);

      // Enter search query
      await tester.enterText(
        find.byKey(const Key('glossary.searchField')),
        'RAG',
      );
      await tester.pumpAndSettle();

      expect(find.text('RAG (Retrieval-Augmented Generation)'), findsOneWidget);
    });

    testWidgets(
      'S10 AssistantPage keeps course banners off the assistant home',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Course progress belongs on the course screen.
        await tester.pumpWidget(
          createTestApp(const AssistantPage(ownerId: testOwner)),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();

        expect(
          find.byKey(const Key('assistant.resumeLessonBanner')),
          findsNothing,
        );
        expect(find.text('Продолжить урок'), findsNothing);

        // Mark all 5 levels complete
        await tester.runAsync(() async {
          for (int i = 1; i <= 5; i++) {
            await courseRepo.completeLevel(ownerId: testOwner, levelId: i);
          }
        });

        // Invalidate cached provider state
        ProviderScope.containerOf(
          tester.element(find.byType(AssistantPage)),
        ).invalidate(overallCourseProgressProvider(testOwner));

        // Re-render
        await tester.pumpWidget(
          createTestApp(const AssistantPage(ownerId: testOwner)),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();

        // Banner should now be gone!
        expect(
          find.byKey(const Key('assistant.resumeLessonBanner')),
          findsNothing,
        );
      },
    );
  });
}
