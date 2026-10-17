import 'dart:async';
import 'package:builder/gallery/catalog.dart';
import 'package:builder/ui_kit/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget harness(Widget child, {double scale = 1}) => MaterialApp(
  theme: BuilderTheme.light,
  home: MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(scale),
      disableAnimations: true,
    ),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final onest = FontLoader('Onest');
    for (final weight in [400, 500, 600, 700]) {
      onest.addFont(rootBundle.load('assets/fonts/Onest-$weight.ttf'));
    }
    await onest.load();
    await (FontLoader(
      'JetBrainsMono',
    )..addFont(rootBundle.load('assets/fonts/JetBrainsMono-500.ttf'))).load();
  });

  for (final size in [
    const Size(360, 780),
    const Size(390, 844),
    const Size(430, 932),
    const Size(1440, 1000),
  ]) {
    for (var section = 0; section < 4; section++) {
      testWidgets(
        'Section $section fits ${size.width} with ${size.width < 1000 ? '130%' : '100%'} text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: BuilderTheme.light,
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(size.width < 1000 ? 1.3 : 1),
                  disableAnimations: true,
                ),
                child: BuilderCatalog(initialSection: section),
              ),
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text('UI Kit'), findsOneWidget);
        },
      );
    }
  }

  testWidgets('Desktop controls keep accessible tap target sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        Column(
          children: [
            BuilderButton(label: 'Продолжить', onPressed: () {}),
            BuilderIconButton(
              icon: BuilderGlyph.settings,
              label: 'Настройки',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(TextButton)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byType(IconButton)).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byType(IconButton)).width,
      greaterThanOrEqualTo(44),
    );
  }, variant: TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('Data chip opens its explanation and can be dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const BuilderDataChip(DataLocation.cloud)));
    await tester.tap(find.text(DataLocation.cloud.label));
    await tester.pumpAndSettle();
    expect(find.text(DataLocation.cloud.explanation), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.text(DataLocation.cloud.explanation), findsNothing);
  });

  testWidgets('Composer rejects whitespace and clears a submitted message', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(harness(BuilderComposer(onSend: sent.add)));
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    final send = find.byTooltip('Отправить сообщение');
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '  Проверьте задание  ');
    await tester.pump();
    await tester.tap(send);
    await tester.pump();
    expect(sent, ['Проверьте задание']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('Confirmation executes once and preserves completion state', (
    tester,
  ) async {
    var calls = 0;
    final operation = Completer<void>();
    await tester.pumpWidget(
      harness(
        BuilderActionCard(
          title: 'Создать событие',
          details: 'Четверг, 10:30',
          onConfirm: () {
            calls++;
            return operation.future;
          },
        ),
      ),
    );
    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    expect(find.text('Создаём…'), findsOneWidget);
    await tester.tap(find.text('Создаём…'));
    expect(calls, 1);
    operation.complete();
    await tester.pumpAndSettle();
    expect(find.text('Выполнено'), findsOneWidget);
    expect(find.text('Подтвердить'), findsNothing);
  });

  testWidgets(
    'Failed confirmation can be retried; cancellation does not execute',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        harness(
          BuilderActionCard(
            title: 'Создать событие',
            details: 'Четверг',
            onConfirm: () async {
              calls++;
              throw StateError('offline');
            },
          ),
        ),
      );
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(
        find.text('Действие не выполнено. Попробуйте ещё раз.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(find.text('Отменено'), findsOneWidget);
      expect(calls, 2);
    },
  );

  testWidgets('Gallery navigation switches to the interactive character', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: BuilderTheme.light, home: const BuilderCatalog()),
    );
    await tester.tap(find.text('Персонаж'));
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(5);
    await tester.pump();
    expect(find.text('Уровень 5 из 5 · ИИ'), findsOneWidget);
  });
}
