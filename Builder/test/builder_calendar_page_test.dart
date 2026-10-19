import 'dart:convert';
import 'package:builder/features/calendar/infrastructure/builder_calendar_client.dart';
import 'package:builder/features/calendar/presentation/builder_calendar_page.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('creates only after explicit save and refreshes occurrences', (
    tester,
  ) async {
    var created = false;
    final client = BuilderCalendarClient(
      CraftAiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            expect(jsonDecode(request.body)['title'], 'Новый урок');
            expect(request.headers['Idempotency-Key'], isNotEmpty);
            created = true;
            return http.Response('{}', 201);
          }
          return http.Response(
            jsonEncode({
              'items': created
                  ? [
                      {
                        'eventId': 'id',
                        'title': 'Новый урок',
                        'start': '2026-10-19T09:00:00',
                        'end': '2026-10-19T10:00:00',
                        'timeZone': 'Asia/Almaty',
                      },
                    ]
                  : [],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [builderCalendarClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: BuilderCalendarPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('В этом месяце нет событий.'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Новый урок');
    expect(created, false);
    await tester.tap(find.text('Сохранить на сервере'));
    await tester.pumpAndSettle();
    expect(created, true);
    expect(find.text('Новый урок'), findsOneWidget);
  });

  testWidgets('failure never becomes an empty or demo calendar', (
    tester,
  ) async {
    final client = BuilderCalendarClient(
      CraftAiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) async => http.Response('{}', 500)),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [builderCalendarClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: BuilderCalendarPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Проверьте соединение'), findsOneWidget);
    expect(find.text('В этом месяце нет событий.'), findsNothing);
    expect(find.text('Урок математики 7Б'), findsNothing);
  });
}
