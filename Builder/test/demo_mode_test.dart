// Run in a real browser: flutter test --platform chrome test/demo_mode_test.dart
import 'package:builder/demo/demo_app.dart';
import 'package:builder/features/agents/domain/lab_agent.dart';
import 'package:builder/ui_kit/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DemoEnvironment> mountDemo(
  WidgetTester tester, {
  Size size = const Size(1100, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final environment = await DemoEnvironment.create();
  await tester.pumpWidget(DemoApp(key: UniqueKey(), environment: environment));
  await tester.pumpAndSettle();
  return environment;
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(finder, 350, scrollable: scrollable);
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> back(WidgetTester tester) =>
    tap(tester, find.byType(BackButton).last);

Future<void> openAgent(
  WidgetTester tester, [
  String name = 'Математика · 5 класс',
]) async {
  final card = find.ancestor(
    of: find.text(name),
    matching: find.byType(BuilderCard),
  );
  await tap(
    tester,
    find.descendant(
      of: card,
      matching: find.widgetWithText(TextButton, 'Открыть'),
    ),
  );
}

Future<void> menu(WidgetTester tester, String id, String action) async {
  await tap(tester, find.byKey(ValueKey('agent-menu-$id')));
  await tap(tester, find.text(action));
}

Future<void> send(WidgetTester tester, String prompt) async {
  final input = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Введите задачу для агента...',
  );
  await tester.enterText(input, prompt);
  await tap(tester, find.byTooltip('Отправить'));
}

String output(WidgetTester tester) {
  final result = find.byType(SelectableText);
  final visibleText = [
    for (final element in find.byType(Text).evaluate())
      (element.widget as Text).data,
  ];
  expect(result, findsWidgets, reason: visibleText.join('\n'));
  return tester.widget<SelectableText>(result.last).data!;
}

void main() {
  testWidgets('demo starts with two agents and a persistent disclosure', (
    tester,
  ) async {
    await mountDemo(tester);
    expect(find.text('2 из 5'), findsOneWidget);
    expect(find.text('Математика · 5 класс'), findsOneWidget);
    expect(find.text('Русский язык · 7 класс'), findsOneWidget);
    expect(find.textContaining('ДЕМО · Без сервера и ИИ'), findsOneWidget);
    await openAgent(tester);
    expect(find.text('Попробуйте агента'), findsOneWidget);
    await tap(tester, find.text('Открыть демодиалог'));
    await send(tester, 'Подготовь задания по дробям');
    expect(output(tester), contains('ДЕМО: ответ по шаблону'));
    expect(output(tester), contains('1/7 + 2/7'));
    expect(find.textContaining('ДЕМО · Без сервера и ИИ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'save requires approval; denial does not write; trace and search show approved material',
    (tester) async {
      final environment = await mountDemo(tester);
      await openAgent(tester);
      await tap(tester, find.text('Открыть демодиалог'));
      await send(tester, 'Сохрани материал');
      expect(
        await environment.runtime.listMaterials('demo-math'),
        hasLength(1),
      );
      await tap(tester, find.text('Отклонить'));
      expect(output(tester), contains('сохранение отклонено'));
      expect(
        await environment.runtime.listMaterials('demo-math'),
        hasLength(1),
      );
      await send(tester, 'Сохрани материал');
      await tap(tester, find.text('Подтвердить'));
      expect(output(tester), contains('материал сохранён'));
      expect(
        await environment.runtime.listMaterials('demo-math'),
        hasLength(2),
      );
      expect(
        await environment.runtime.listMaterials('demo-russian'),
        hasLength(1),
      );
      await tap(tester, find.widgetWithText(TextButton, 'Как выполнено'));
      await reveal(tester, find.textContaining('ID материала:'));
      expect(find.textContaining('ID материала:'), findsOneWidget);
      await back(tester);
      await send(tester, 'Найди материалы');
      expect(output(tester), contains('Дроби: памятка'));
      expect(output(tester), contains('Задания · демо'));
      expect(output(tester), isNot(contains('Причастие: памятка')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings add material and memory; disabling save is enforced in the chat',
    (tester) async {
      final environment = await mountDemo(tester);
      await openAgent(tester);
      await tap(tester, find.text('Материалы, память и настройки'));
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Название материала',
      );
      await reveal(tester, title);
      await tester.enterText(title, 'Проверка Chrome');
      final content = find.byKey(const Key('material_content_field'));
      await reveal(tester, content);
      await tester.enterText(content, 'Учебный материал из браузера.');
      await tap(tester, find.text('Сохранить материал'));
      expect(
        (await environment.runtime.listMaterials(
          'demo-math',
        )).any((item) => item.title == 'Проверка Chrome'),
        isTrue,
      );
      final memory = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Добавить факт памяти...',
      );
      await reveal(tester, memory);
      await tester.enterText(memory, 'Новый учебный факт');
      await tap(tester, find.widgetWithText(FilledButton, 'Добавить'));
      expect(await environment.runtime.listMemory('demo-math'), hasLength(2));
      final saveSwitch = find.widgetWithText(
        SwitchListTile,
        'Сохранение материалов (save_material)',
      );
      // Return to the start of the settings list, which lazily builds the switches.
      final scrollable = find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(saveSwitch, -350, scrollable: scrollable);
      await tap(tester, saveSwitch);
      await tap(tester, find.widgetWithText(TextButton, 'Сохранить'));
      expect(find.text('Настройки применены'), findsOneWidget);
      // Let the save notification expire before tapping the chat input bar.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await back(tester);
      await tap(tester, find.text('Открыть демодиалог'));
      await send(tester, 'Сохрани материал');
      expect(output(tester), contains('сохранение запрещено'));
      expect(find.text('Подтвердить'), findsNothing);
      expect(
        await environment.runtime.listMaterials('demo-math'),
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'copy contains config only, reset is scoped, five-agent limit and delete work',
    (tester) async {
      final environment = await mountDemo(tester);
      await menu(tester, 'demo-math', 'Копировать');
      expect(find.text('3 из 5'), findsOneWidget);
      var agents = (await environment.agents.load()).agents;
      final copy = agents.singleWhere(
        (agent) => agent.id != 'demo-math' && agent.id != 'demo-russian',
      );
      expect(
        copy.instruction,
        agents.singleWhere((agent) => agent.id == 'demo-math').instruction,
      );
      expect(await environment.runtime.listMaterials(copy.id), isEmpty);
      expect(await environment.runtime.listMemory(copy.id), isEmpty);
      await menu(tester, 'demo-math', 'Сбросить данные');
      await tap(tester, find.widgetWithText(FilledButton, 'Сбросить данные'));
      expect(await environment.runtime.listMaterials('demo-math'), isEmpty);
      expect(await environment.runtime.listMemory('demo-math'), isEmpty);
      expect(
        await environment.runtime.listMaterials('demo-russian'),
        hasLength(1),
      );
      await menu(tester, 'demo-russian', 'Копировать');
      await menu(tester, 'demo-russian', 'Копировать');
      expect(find.text('5 из 5'), findsOneWidget);
      await menu(tester, 'demo-russian', 'Копировать');
      expect(find.textContaining('Можно создать до 5 агентов'), findsWidgets);
      expect((await environment.agents.load()).agents, hasLength(5));
      await menu(tester, copy.id, 'Удалить агента');
      await tap(tester, find.widgetWithText(FilledButton, 'Удалить агента'));
      expect(find.text('4 из 5'), findsOneWidget);
      agents = (await environment.agents.load()).agents;
      expect(agents.any((agent) => agent.id == copy.id), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wizard creates an agent, rename persists, instruction changes the template',
    (tester) async {
      final environment = await mountDemo(tester);
      await tap(tester, find.text('Создать агента'));
      await tester.enterText(
        find.byKey(const ValueKey('agent-name')),
        'Демо Chrome',
      );
      await tester.enterText(
        find.byKey(const ValueKey('agent-subject')),
        'Математика',
      );
      await tester.enterText(find.byKey(const ValueKey('agent-grade')), '5');
      final requirements = find.byKey(const ValueKey('agent-requirements'));
      await reveal(tester, requirements);
      await tester.enterText(requirements, 'Три задания');
      await tap(tester, find.text('Составить инструкцию'));
      final instruction = find.byKey(const ValueKey('agent-instruction'));
      await reveal(tester, instruction);
      await tester.enterText(instruction, 'Отвечай кратко.');
      await tap(tester, find.widgetWithText(FilledButton, 'Создать агента'));
      expect(find.text('3 из 5'), findsOneWidget);
      final LabAgent created = (await environment.agents.load()).agents
          .singleWhere((agent) => agent.name == 'Демо Chrome');
      await menu(tester, created.id, 'Переименовать');
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        'Переименован в Chrome',
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Сохранить'));
      await openAgent(tester, 'Переименован в Chrome');
      await tap(tester, find.text('Открыть демодиалог'));
      await send(tester, 'Задания');
      expect(output(tester), contains('1/7 + 2/7'));
      expect(output(tester), isNot(contains('Найди разность')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fresh demo restores seed data after changes', (tester) async {
    final environment = await mountDemo(tester);
    await menu(tester, 'demo-math', 'Удалить агента');
    await tap(tester, find.widgetWithText(FilledButton, 'Удалить агента'));
    expect(find.text('1 из 5'), findsOneWidget);
    expect((await environment.agents.load()).agents, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final restored = await mountDemo(tester);
    expect(find.text('2 из 5'), findsOneWidget);
    expect(await restored.runtime.listMaterials('demo-math'), hasLength(1));
    expect(await restored.runtime.listMemory('demo-math'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact Chrome layout renders the banner, agents and chat without overflow',
    (tester) async {
      await mountDemo(tester, size: const Size(390, 844));
      expect(find.text('2 из 5'), findsOneWidget);
      await openAgent(tester);
      await tap(tester, find.text('Открыть демодиалог'));
      await send(tester, 'Задания');
      expect(output(tester), contains('ДЕМО:'));
      expect(tester.takeException(), isNull);
    },
  );
}
