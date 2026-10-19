import 'dart:io';
import 'dart:ui' as ui;

import 'package:builder/features/course/domain/course_topic.dart';
import 'package:builder/features/course/presentation/course_character.dart';
import 'package:builder/ui_kit/identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await rootBundle.loadString('assets/character.svg');
  });
  testWidgets('Legacy achievements do not unlock Skills or automation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CourseCharacter(completedLevels: {1, 2, 3, 4, 5, 999}),
      ),
    );
    await tester.pumpAndSettle();
    final character = tester.widget<BuilderCharacter>(
      find.byType(BuilderCharacter),
    );
    expect(character.unlockedModules, {1, 2, 3, 4, 5});
    expect(character.semanticLabel, contains('уровень 6 из 11'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Skills activates its own module independently of knowledge', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CourseCharacter(completedLevels: {1, 2, 10})),
    );
    await tester.pumpAndSettle();
    final character = tester.widget<BuilderCharacter>(
      find.byType(BuilderCharacter),
    );
    expect(character.unlockedModules, {1, 2, 10});
    expect(character.semanticLabel, contains('уровень 3 из 11'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'All eleven modules and compact character render at small sizes',
    (tester) async {
      final topics = CourseTopic.values.map((topic) => topic.storageId).toSet();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: Colors.white,
                child: Wrap(
                  children: [
                    for (final completed in [
                      <int>{},
                      {1, 2, 10},
                      {1, 2, 3, 4, 5},
                      topics,
                    ])
                      CourseCharacter(completedLevels: completed, size: 168),
                    CourseCharacter(
                      completedLevels: topics,
                      size: 56,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() => vg.waitForPendingDecodes());
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsNWidgets(5));
      expect(tester.takeException(), isNull);
      final preview = Platform.environment['CHARACTER_PREVIEW_PATH'];
      if (preview != null) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(preview).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
}
