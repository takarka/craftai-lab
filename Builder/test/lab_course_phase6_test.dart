import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/features/agents/agents_providers.dart';
import 'package:builder/features/agents/infrastructure/agents_cache.dart';
import 'package:builder/features/agents/infrastructure/agents_repository.dart';
import 'package:builder/features/agents/infrastructure/lab_api_client.dart';
import 'package:builder/features/agents/presentation/agents_page.dart';
import 'package:builder/features/course/lab_course_mvp.dart';
import 'package:builder/features/lab_runtime/domain/lab_run_models.dart';
import 'package:builder/features/lab_runtime/infrastructure/lab_runtime_api.dart';
import 'package:builder/features/lab_runtime/presentation/lab_agent_workspace_page.dart';
import 'package:builder/features/session/domain/auth_tokens.dart';
import 'package:builder/features/session/infrastructure/secure_token_storage.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _StubRuntimeApi extends LabRuntimeApi {
  @override
  Future<List<LabModelInfo>> listModels() async => const [
    LabModelInfo(
      modelId: 'google/gemini-2.5-flash',
      available: true,
      supportsTools: true,
      supportsVision: true,
    ),
  ];

  @override
  Future<LabRun> createRun({
    required String agentId,
    required String prompt,
    required String idempotencyKey,
    List<String> imageDataUris = const [],
  }) async => LabRun(
    id: 'run-1',
    agentId: agentId,
    agentVersionId: 'v1',
    epoch: 0,
    modelId: 'google/gemini-2.5-flash',
    status: 'completed',
    stopReason: 'completed',
    finalOutput: 'Три вопроса по теме испарения.',
  );

  @override
  Future<LabRun> getRun(String runId) async => throw UnimplementedError();
  @override
  Future<LabRun> cancelRun(String runId) async => throw UnimplementedError();
  @override
  Future<LabRun> resolveAction({
    required String runId,
    required String actionId,
    required String decision,
    Map<String, dynamic>? params,
  }) async => throw UnimplementedError();
  @override
  Future<List<LabMaterialItem>> listMaterials(String agentId) async => const [];
  @override
  Future<LabMaterialItem> createMaterial({
    required String agentId,
    required String title,
    required String content,
    String source = 'text',
  }) async => throw UnimplementedError();
  @override
  Future<void> deleteMaterial({
    required String agentId,
    required String materialId,
  }) async {}
  @override
  Future<LabPhotoExtraction> uploadPhoto({
    required String agentId,
    required String fileName,
    required List<int> bytes,
  }) async => throw UnimplementedError();
  @override
  Future<List<LabMemoryItem>> listMemory(String agentId) async => const [];
  @override
  Future<LabMemoryItem> createMemory({
    required String agentId,
    required String content,
  }) async => throw UnimplementedError();
  @override
  Future<void> deleteMemory({
    required String agentId,
    required String entryId,
  }) async {}
  @override
  Future<List<LabSkillItem>> listSkills(String agentId) async => const [];
  @override
  Future<LabSkillItem> updateSkill({
    required String agentId,
    required String slug,
    required bool enabled,
    required String overrideText,
    required bool allowSave,
    required bool allowSearch,
  }) async => throw UnimplementedError();
}

void main() {
  test('LabCourseCatalog defines 7 PRD lessons and analytics strips texts', () {
    expect(LabCourseCatalog.lessons.map((l) => l.id), [1, 2, 3, 4, 5, 6, 7]);
    expect(LabCourseCatalog.byId(3).requiresMaterialId, isTrue);
    expect(LabCourseCatalog.byId(7).requiresSecondAgentWithoutWizard, isTrue);

    final analytics = LabCourseAnalytics();
    analytics.record('run_completed', {
      'lesson_id': 3,
      'status': 'completed',
      'prompt': 'Секретный текст запроса учителя',
      'material_text': 'Текст учебного фрагмента',
      'instruction': 'Системная инструкция',
    });
    expect(analytics.events.single, {
      'event': 'run_completed',
      'lesson_id': 3,
      'status': 'completed',
    });
  });

  testWidgets(
    'Lesson 3 requires save_material ID; progress survives restart and upgrade',
    (tester) async {
      LabRunCompletionEvidence nextEvidence = const LabRunCompletionEvidence(
        runId: 'r1',
        status: 'completed',
        materialId: null,
      );
      LabCourseProgressState savedServerProgress = const LabCourseProgressState(
        completedLessons: [1, 2],
        currentLesson: 3,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LabLessonPlayerPage(
            lesson: LabCourseCatalog.byId(3),
            initialProgress: savedServerProgress,
            onExecutePracticeRun: () async => nextEvidence,
            onSaveProgress: (updated) async {
              savedServerProgress = updated;
            },
          ),
        ),
      );

      // Step 1 -> Step 2 (Prediction)
      await tester.tap(find.text('К прогнозу'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          'Включённое разрешение save_material и подтверждение пользователя',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('К изменению агента'));
      await tester.pumpAndSettle();

      // Step 3 (Change) -> Step 4 (Run)
      await tester.tap(find.text('Изменение внесено в настройках агента'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Перейти к запуску'));
      await tester.pumpAndSettle();

      // Run without material_id is blocked
      await tester.tap(find.byKey(const Key('lab_lesson_execute_run')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('необходим реальный вызов save_material'),
        findsOneWidget,
      );
      final nextBtnBlocked = tester.widget<FilledButton>(
        find.byKey(const Key('lab_lesson_after_run_next')),
      );
      expect(nextBtnBlocked.onPressed, isNull);

      // Run with material_id unlocks next step
      nextEvidence = const LabRunCompletionEvidence(
        runId: 'r2',
        status: 'completed',
        materialId: 'mat-101',
      );
      await tester.tap(find.byKey(const Key('lab_lesson_execute_run')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lab_lesson_after_run_next')));
      await tester.pumpAndSettle();

      // Step 5 (Comparison) -> Step 6 (Independent task)
      await tester.tap(find.text('Результат сравнён с прогнозом и трассой'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('К самостоятельному заданию'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Самостоятельное задание выполнено'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lab_lesson_complete_btn')));
      await tester.pumpAndSettle();

      expect(savedServerProgress.completedLessons, [1, 2, 3]);
      final upgraded = savedServerProgress.mergeUpgrade('0.3');
      expect(upgraded.courseVersion, '0.3');
      expect(upgraded.completedLessons, [1, 2, 3]);
    },
  );

  testWidgets('Lesson 7 requires second agent without wizard on second model', (
    tester,
  ) async {
    var evidence = const LabRunCompletionEvidence(
      runId: 'r7-a',
      status: 'completed',
      createdSecondAgentWithoutWizard: false,
      usedSecondModel: false,
    );
    LabCourseProgressState progress = const LabCourseProgressState(
      completedLessons: [1, 2, 3, 4, 5, 6],
      currentLesson: 7,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LabLessonPlayerPage(
          lesson: LabCourseCatalog.byId(7),
          initialProgress: progress,
          onExecutePracticeRun: () async => evidence,
          onSaveProgress: (updated) async => progress = updated,
        ),
      ),
    );

    await tester.tap(find.text('К прогнозу'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Да, агенты изолированы, а прогресс курса хранится отдельно'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('К изменению агента'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменение внесено в настройках агента'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Перейти к запуску'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('lab_lesson_execute_run')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('без пошагового мастера на второй модели'),
      findsOneWidget,
    );

    evidence = const LabRunCompletionEvidence(
      runId: 'r7-b',
      status: 'completed',
      createdSecondAgentWithoutWizard: true,
      usedSecondModel: true,
    );
    await tester.tap(find.byKey(const Key('lab_lesson_execute_run')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab_lesson_after_run_next')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Результат сравнён с прогнозом и трассой'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('К самостоятельному заданию'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Самостоятельное задание выполнено'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab_lesson_complete_btn')));
    await tester.pumpAndSettle();

    expect(progress.completedLessons, [1, 2, 3, 4, 5, 6, 7]);
  });

  testWidgets(
    'AgentsPage opens LabAgentWorkspacePage chat via /agents/:id/chat route',
    (tester) async {
      final tokens = InMemorySecureTokenStorage();
      await tokens.writeSession(
        ownerId: 'alice',
        tokens: AuthTokens(
          accessToken: 'tok',
          refreshToken: 'ref',
          expiresAtUtc: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      final repo = AgentsRepository(
        api: LabApiClient(
          baseUri: Uri.parse('https://lab.test'),
          client: MockClient(
            (_) async => http.Response(
              '{"agents":[{"id":"a1","name":"Естествознание 5","version":1,"epoch":0,"instruction":"Правило"}],"limit":5}',
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
          tokens: tokens,
          ownerId: 'alice',
        ),
        cache: MemoryAgentsCache(),
      );

      final router = GoRouter(
        initialLocation: '/agents',
        routes: [
          GoRoute(
            path: '/agents',
            builder: (_, _) => const AgentsPage(ownerId: 'alice'),
            routes: [
              GoRoute(
                path: ':agentId/chat',
                builder: (_, state) => LabAgentWorkspacePage(
                  ownerId: 'alice',
                  agentId: state.pathParameters['agentId']!,
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentsRepositoryProvider('alice').overrideWithValue(repo),
            labRuntimeApiProvider.overrideWithValue(_StubRuntimeApi()),
            sessionProvider.overrideWith(
              (_) => Stream.value(
                AuthenticatedSession(
                  ownerId: 'alice',
                  onboardingComplete: true,
                ),
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('agent-chat-a1')));
      await tester.pumpAndSettle();
      expect(find.text('Естествознание 5'), findsOneWidget);
      expect(find.textContaining('Лимиты: 0/3 инструментов'), findsOneWidget);
    },
  );
}
