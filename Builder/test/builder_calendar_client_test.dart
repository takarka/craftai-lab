import 'dart:convert';
import 'package:builder/features/calendar/infrastructure/builder_calendar_client.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'calendar sends all seven operations with concurrency and retry keys',
    () async {
      final requests = <http.Request>[];
      final calendar = BuilderCalendarClient(
        CraftAiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((request) async {
            requests.add(request);
            return http.Response(
              request.method == 'DELETE' ? '' : '{}',
              request.method == 'DELETE' ? 204 : 200,
            );
          }),
        ),
      );
      final input = {
        'title': 'Сабақ',
        'start': '2026-10-19T09:00:00',
        'end': '2026-10-19T10:00:00',
        'timeZone': 'Asia/Almaty',
        'allDay': false,
        'reminders': <int>[],
        'recurrence': {
          'frequency': 'weekly',
          'byWeekday': ['mon'],
        },
      };
      await calendar.occurrences('2026-10-01', '2026-10-31');
      await calendar.event('event-id');
      await calendar.create(input, idempotencyKey: 'stable-key');
      await calendar.replace('event-id', 3, input);
      await calendar.delete('event-id', followingFrom: '2026-10-26');
      await calendar.overrideOccurrence('event-id', '2026-10-19', {
        'canceled': true,
      });
      await calendar.changes(cursor: 'opaque+/=');
      expect(requests.map((r) => r.method), [
        'GET',
        'GET',
        'POST',
        'PUT',
        'DELETE',
        'PUT',
        'GET',
      ]);
      expect(requests[0].url.queryParameters['from'], '2026-10-01');
      expect(requests[2].headers['Idempotency-Key'], 'stable-key');
      expect(jsonDecode(requests[2].body), input);
      expect(requests[3].headers['If-Match'], '"3"');
      expect(requests[4].url.queryParameters, {
        'scope': 'following',
        'from': '2026-10-26',
      });
      expect(
        requests[5].url.path,
        '/builder/calendar/events/event-id/occurrences/2026-10-19',
      );
      expect(requests[6].url.queryParameters['cursor'], 'opaque+/=');
    },
  );

  test('version conflict remains a failure instead of overwriting', () async {
    var calls = 0;
    final calendar = BuilderCalendarClient(
      CraftAiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{"code":"calendar.version-conflict"}', 412);
        }),
      ),
    );
    await expectLater(
      calendar.replace('id', 1, {}),
      throwsA(
        isA<CraftAiException>().having((e) => e.statusCode, 'status', 412),
      ),
    );
    expect(calls, 1);
  });
}
