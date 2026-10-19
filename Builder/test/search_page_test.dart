import 'dart:async';
import 'dart:convert';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:builder/features/models/model_providers.dart';
import 'package:builder/features/tools/presentation/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response ok(List<Map<String, String>> results) => http.Response(
  jsonEncode({'requestId': 'r', 'source': 'provider', 'durationMs': 5, 'results': results}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<List<Uri>> pump(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  Locale locale = const Locale('ru'),
  bool openSucceeds = true,
}) async {
  final opened = <Uri>[];
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        craftAiClientProvider.overrideWithValue(
          CraftAiClient(baseUri: Uri.parse('https://api.example.test'), httpClient: MockClient(handler)),
        ),
        searchLinkOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return openSucceeds;
        }),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const SearchPage(),
      ),
    ),
  );
  return opened;
}

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.tap(find.text('Найти'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows sources and opens a link only after confirmation', (tester) async {
    final opened = await pump(tester, (_) async => ok([
      {'title': 'Планирование урока', 'url': 'https://example.test/plan', 'snippet': 'Шаблон', 'source': 'example.test'},
    ]));
    await search(tester, 'планирование');

    expect(find.text('Планирование урока'), findsOneWidget);
    expect(find.textContaining('example.test'), findsWidgets);

    await tester.tap(find.byTooltip('Открыть источник'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty, reason: 'no navigation before confirming');
    expect(find.textContaining('https://example.test/plan'), findsOneWidget);
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'https://example.test/plan');
  });

  testWidgets('declining the dialog opens nothing; an open failure is reported', (tester) async {
    final opened = await pump(tester, (_) async => ok([
      {'title': 'A', 'url': 'https://example.test/a', 'snippet': '', 'source': 's'},
    ]), openSucceeds: false);
    await search(tester, 'a');
    await tester.tap(find.byTooltip('Открыть источник'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);

    await tester.tap(find.byTooltip('Открыть источник'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось открыть ссылку.'), findsOneWidget);
  });

  testWidgets('empty result, outage and no network are told apart', (tester) async {
    var mode = 'empty';
    await pump(tester, (_) async {
      if (mode == 'down') return http.Response('{}', 503);
      if (mode == 'offline') throw http.ClientException('no route');
      return ok([]);
    });

    await search(tester, 'ничего');
    expect(find.textContaining('ничего не найдено'), findsOneWidget);

    mode = 'down';
    await tester.tap(find.text('Найти'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Это сбой сервиса'), findsOneWidget);
    expect(find.textContaining('ничего не найдено'), findsNothing);

    mode = 'offline';
    await tester.tap(find.text('Найти'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Нет соединения'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('cancel returns to idle and ignores the late answer', (tester) async {
    final gate = Completer<http.Response>();
    await pump(tester, (_) => gate.future);
    await tester.enterText(find.byType(TextField), 'долго');
    await tester.tap(find.text('Найти'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Отменить'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gate.complete(ok([
      {'title': 'Поздний ответ', 'url': 'https://example.test/late', 'snippet': '', 'source': 's'},
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Поздний ответ'), findsNothing);
    expect(find.textContaining('сбой'), findsNothing);
  });

  testWidgets('result text is shown as plain text and unsafe links never appear', (tester) async {
    await pump(tester, (_) async => ok([
      {'title': '<b>Жирный</b> [ссылка](https://evil.test)', 'url': 'https://example.test/x', 'snippet': 'x', 'source': 's'},
      {'title': 'Опасная', 'url': 'javascript:alert(1)', 'snippet': 'x', 'source': 's'},
    ]));
    await search(tester, 'x');
    expect(find.text('<b>Жирный</b> [ссылка](https://evil.test)'), findsOneWidget);
    expect(find.text('Опасная'), findsNothing);
  });

  testWidgets('Kazakh strings and a privacy notice are present', (tester) async {
    await pump(tester, (_) async => ok([]), locale: const Locale('kk'));
    await tester.pumpAndSettle();
    expect(find.text('CraftAI іздеуі'), findsOneWidget);
    expect(find.textContaining('жеке деректерін жазбаңыз'), findsOneWidget);
  });
}
