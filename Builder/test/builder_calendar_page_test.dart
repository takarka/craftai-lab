import 'dart:convert';

import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/features/calendar/domain/calendar_models.dart';
import 'package:builder/features/calendar/domain/recurrence_expander.dart';
import 'package:builder/features/calendar/infrastructure/builder_calendar_client.dart';
import 'package:builder/features/calendar/presentation/calendar_event_editor.dart' show formatDay;
import 'package:builder/features/calendar/presentation/builder_calendar_page.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Minimal stateful double of the Builder calendar API.
class FakeCalendarServer {
  final events = <String, Map<String, dynamic>>{};
  final canceled = <String>{};
  final requests = <http.Request>[];
  bool down = false;
  int? replaceStatus;
  int _next = 0;

  static const _headers = {'content-type': 'application/json; charset=utf-8'};

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: _headers);

  void seed(Map<String, dynamic> input) {
    final id = 'e${++_next}';
    events[id] = {...input, 'id': id, 'version': 1};
  }

  BuilderCalendarClient get client => BuilderCalendarClient(
    CraftAiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return handle(request);
      }),
    ),
  );

  Future<http.Response> handle(http.Request request) async {
    if (down) return http.Response('{}', 503);
    final path = request.url.path.replaceFirst('/builder/calendar', '');
    if (request.method == 'POST' && path == '/events') {
      seed(jsonDecode(request.body) as Map<String, dynamic>);
      return _json(events.values.last, 201);
    }
    if (request.method == 'GET' && path == '/changes') {
      return _json({
        'items': [
          for (final e in events.values) {'type': 'upsert', 'eventId': e['id'], 'event': e},
        ],
        'nextCursor': 'c$_next',
        'hasMore': false,
      });
    }
    if (request.method == 'GET' && path == '/events') {
      final from = request.url.queryParameters['from']!;
      final to = request.url.queryParameters['to']!;
      final items = RecurrenceExpander.occurrences(
        events.values.map(CalendarEvent.fromJson),
        from,
        to,
        [
          for (final key in canceled)
            OccurrenceOverride(eventId: key.split('|')[0], date: key.split('|')[1], canceled: true),
        ],
      );
      return _json({
        'from': from,
        'to': to,
        'items': [
          for (final o in items)
            {
              'eventId': o.eventId,
              'occurrenceDate': o.occurrenceDate,
              'title': o.title,
              'allDay': o.allDay,
              'start': o.start,
              'end': o.end,
              if (o.timeZone != null) 'timeZone': o.timeZone,
              'isOverride': false,
            },
        ],
      });
    }
    final segments = path.split('/');
    final id = segments.length > 2 ? segments[2] : '';
    if (request.method == 'GET' && segments.length == 3) return _json(events[id]!);
    if (request.method == 'PUT' && segments.length == 3) {
      if (replaceStatus != null) return http.Response('{}', replaceStatus!);
      events[id] = {
        ...(jsonDecode(request.body) as Map<String, dynamic>),
        'id': id,
        'version': (events[id]!['version'] as int) + 1,
      };
      return _json(events[id]!);
    }
    if (request.method == 'PUT' && segments.length == 5) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['canceled'] == true) canceled.add('$id|${segments[4]}');
      return _json({});
    }
    if (request.method == 'DELETE') {
      if (request.url.queryParameters['scope'] == 'all') events.remove(id);
      return http.Response('', 204);
    }
    return http.Response('{}', 404);
  }
}

String day(DateTime value) => formatDay(value);

Map<String, dynamic> lesson({String title = 'Алгебра 7Б', bool weekly = false}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return {
    'title': title,
    'allDay': false,
    'start': '${day(today)}T09:00:00',
    'end': '${day(today)}T09:45:00',
    'timeZone': 'Asia/Almaty',
    'reminders': <int>[],
    if (weekly) 'recurrence': {'frequency': 'weekly', 'byWeekday': [weekdayName(today.weekday)]},
  };
}

Future<void> pumpPage(
  WidgetTester tester,
  FakeCalendarServer server, {
  Locale locale = const Locale('ru'),
}) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [builderCalendarClientProvider.overrideWithValue(server.client)],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const BuilderCalendarPage(ownerId: 'teacher'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('creates only after explicit save and shows the server event', (tester) async {
    final server = FakeCalendarServer();
    await pumpPage(tester, server);
    expect(find.text('В этом месяце нет событий.'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Новый урок');
    expect(server.requests.where((r) => r.method == 'POST'), isEmpty);
    await tester.tap(find.text('Сохранить на сервере'));
    await tester.pumpAndSettle();

    final post = server.requests.singleWhere((r) => r.method == 'POST');
    expect(post.headers['Idempotency-Key'], isNotEmpty);
    expect(jsonDecode(post.body)['title'], 'Новый урок');
    expect(jsonDecode(post.body)['timeZone'], 'Asia/Almaty');
    expect(find.text('Новый урок'), findsOneWidget);
  });

  testWidgets('failure with no cache never becomes an empty or demo calendar', (tester) async {
    final server = FakeCalendarServer()..down = true;
    await pumpPage(tester, server);
    expect(find.textContaining('Проверьте соединение'), findsOneWidget);
    expect(find.text('Урок математики 7Б'), findsNothing);
  });

  testWidgets('offline shows the cached month with a stale-data notice', (tester) async {
    final server = FakeCalendarServer()..seed(lesson());
    await pumpPage(tester, server);
    expect(find.text('Алгебра 7Б'), findsOneWidget);

    server.down = true;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(find.text('Алгебра 7Б'), findsOneWidget);
    expect(find.textContaining('Показаны данные от'), findsOneWidget);
  });

  testWidgets('a create with no server answer is kept and sent again without a duplicate', (tester) async {
    final server = FakeCalendarServer()..down = true;
    await pumpPage(tester, server);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Совещание');
    await tester.tap(find.text('Сохранить на сервере'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ожидают отправки: Совещание'), findsOneWidget);
    expect(server.events, isEmpty);

    server.down = false;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    final keys = server.requests
        .where((r) => r.method == 'POST')
        .map((r) => r.headers['Idempotency-Key'])
        .toSet();
    expect(keys, hasLength(1), reason: 'every retry reuses one key');
    expect(server.events, hasLength(1));
    expect(find.textContaining('Ожидают отправки'), findsNothing);
    expect(find.text('Совещание'), findsOneWidget);
  });

  testWidgets('a version conflict refreshes and never overwrites', (tester) async {
    final server = FakeCalendarServer()..seed(lesson());
    await pumpPage(tester, server);
    server.replaceStatus = 412;
    await tester.tap(find.text('Алгебра 7Б'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Изменённый');
    await tester.tap(find.text('Сохранить на сервере'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Событие изменилось'), findsOneWidget);
    expect(server.events.values.single['title'], 'Алгебра 7Б');
    final put = server.requests.firstWhere((r) => r.method == 'PUT');
    expect(put.headers['If-Match'], '"1"');
  });

  testWidgets('cancels a single occurrence of a series', (tester) async {
    final server = FakeCalendarServer()..seed(lesson(weekly: true));
    await pumpPage(tester, server);
    await tester.tap(find.byTooltip('Действия').first);
    await tester.pumpAndSettle();
    expect(find.text('Удалить это и следующие'), findsOneWidget);
    await tester.tap(find.text('Отменить только это'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить').last);
    await tester.pumpAndSettle();

    final put = server.requests.lastWhere(
      (r) => r.method == 'PUT' && r.url.path.contains('/occurrences/'),
    );
    expect(jsonDecode(put.body), {'canceled': true});
    expect(find.text('Алгебра 7Б'), findsNothing);
  });

  testWidgets('deleting a whole non-repeating event asks for confirmation', (tester) async {
    final server = FakeCalendarServer()..seed(lesson());
    await pumpPage(tester, server);
    await tester.tap(find.byTooltip('Действия'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить это и следующие'), findsNothing);
    await tester.tap(find.text('Удалить').first);
    await tester.pumpAndSettle();
    expect(server.requests.where((r) => r.method == 'DELETE'), isEmpty);
    await tester.tap(find.text('Удалить').last);
    await tester.pumpAndSettle();

    expect(server.events, isEmpty);
    expect(find.text('Алгебра 7Б'), findsNothing);
  });

  testWidgets('editor keeps repeat rule and exposes it in Kazakh', (tester) async {
    final server = FakeCalendarServer()..seed(lesson(weekly: true));
    await pumpPage(tester, server, locale: const Locale('kk'));
    expect(find.text('Builder күнтізбесі'), findsOneWidget);
    await tester.tap(find.text('Алгебра 7Б'));
    await tester.pumpAndSettle();
    expect(find.text('Қайталау'), findsOneWidget);
    await tester.tap(find.text('Серверде сақтау'));
    await tester.pumpAndSettle();

    final put = server.requests.lastWhere((r) => r.method == 'PUT');
    final recurrence = jsonDecode(put.body)['recurrence'] as Map;
    expect(recurrence['frequency'], 'weekly');
    expect(recurrence['byWeekday'], hasLength(1));
  });
}
