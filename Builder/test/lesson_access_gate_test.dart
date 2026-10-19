import 'package:builder/features/course/course_providers.dart';
import 'package:builder/features/course/domain/course_models.dart';
import 'package:builder/features/course/presentation/lesson_access_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final status in [LevelStatus.locked, LevelStatus.available]) {
    testWidgets('Direct lesson link follows repository status: $status', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            levelStatusProvider((
              ownerId: 'alice',
              levelId: 10,
            )).overrideWith((ref) async => status),
          ],
          child: const MaterialApp(
            home: LessonAccessGate(
              ownerId: 'alice',
              levelId: 10,
              child: Text('interactive-lesson', key: Key('interactive')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('interactive')),
        status == LevelStatus.available ? findsOneWidget : findsNothing,
      );
      if (status == LevelStatus.locked) {
        expect(find.textContaining('Сначала завершите'), findsOneWidget);
      }
    });
  }
}
