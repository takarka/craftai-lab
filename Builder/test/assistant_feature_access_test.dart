import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/app/providers.dart';
import 'package:builder/app/router/app_router.dart';
import 'package:builder/features/assistant/assistant_providers.dart';
import 'package:builder/features/assistant/domain/assistant_config.dart';
import 'package:builder/features/assistant/presentation/assistant_feature_gate.dart';
import 'package:builder/features/course/domain/course_catalog.dart';
import 'package:builder/features/course/course_providers.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const owner = 'access-test';
  test('Access uses completed course progress without a local database', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(completedCourseLevelsProvider(owner).future), isEmpty);
    await container.read(courseRepositoryProvider).completeLevel(ownerId: owner, levelId: 3);
    container.invalidate(completedCourseLevelsProvider(owner));
    expect(await container.read(completedCourseLevelsProvider(owner).future), {3});
  });

  test('Feature levels match the actual course lessons', () {
    for (final lesson in CourseCatalog.levels) {
      if (lesson.targetSkillId != null) {
        expect(lesson.targetSkillId!.level, lesson.id);
      }
    }
  });

  for (var completed = 0; completed <= 5; completed++) {
    testWidgets('Feature access after $completed completed lessons', (
      tester,
    ) async {
      for (final skill in AssistantSkillId.values.where((s) => !s.comingSoon)) {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              completedCourseLevelsProvider(
                owner,
              ).overrideWith((_) => {for (var n = 1; n <= completed; n++) n}),
            ],
            child: MaterialApp(
              home: AssistantFeatureGate(
                ownerId: owner,
                skill: skill,
                builder: (_) => const Text('FEATURE EDITOR'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('FEATURE EDITOR'),
          completed >= skill.level ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('assistant.featureLocked')),
          completed < skill.level ? findsOneWidget : findsNothing,
        );
      }
    });
  }

  testWidgets('Progress failure does not open the editor', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          completedCourseLevelsProvider(
            owner,
          ).overrideWith((_) => throw StateError('offline')),
        ],
        child: MaterialApp(
          home: AssistantFeatureGate(
            ownerId: owner,
            skill: AssistantSkillId.knowledge,
            builder: (_) => const Text('FEATURE EDITOR'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('FEATURE EDITOR'), findsNothing);
    expect(find.byKey(const Key('assistant.featureLocked')), findsOneWidget);
  });

  for (final route in ['instructions', 'knowledge', 'memory', 'tools', 'mcp']) {
    testWidgets('Direct /assistant/$route is locked during first level', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWithValue(
            AsyncData(
              AuthenticatedSession(ownerId: owner, onboardingComplete: true),
            ),
          ),
          completedCourseLevelsProvider(owner).overrideWith((_) => <int>{}),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.go('/assistant/$route');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assistant.featureLocked')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
