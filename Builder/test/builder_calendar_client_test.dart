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
            final path = request.url.path;
            final body = request.method == 'DELETE'
                ? ''
                : request.method != 'GET'
                ? '{}'
                : path.endsWith('/changes')
                ? '{"items":[],"nextCursor":"n","hasMore":false}'
                : path.endsWith('/events')
                ? '{"from":"2026-10-01","to":"2026-10-31","items":[]}'
                : jsonEncode({
                    'id': 'event-id',
                    'version': 3,
                    'title': 'Сабақ',
                    'allDay': false,
                    'start': '2026-10-19T09:00:00',
                    'end': '2026-10-19T10:00:00',
                    'timeZone': 'Asia/Almaty',
                  });
            return http.Response(
              body,
              request.method == 'DELETE' ? 204 : 200,
              headers: {'content-type': 'application/json; charset=utf-8'},
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
      expect(await calendar.occurrences('2026-10-01', '2026-10-31'), isEmpty);
      expect((await calendar.event('event-id')).version, 3);
      await calendar.create(input, idempotencyKey: 'stable-key');
      await calendar.replace('event-id', 3, input);
      await calendar.delete('event-id', followingFrom: '2026-10-26');
      await calendar.overrideOccurrence('event-id', '2026-10-19', {
        'canceled': true,
      });
      expect((await calendar.changes(cursor: 'opaque+/=')).nextCursor, 'n');
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

  test('an empty cursor means a full download and is not sent', () async {
    late http.Request seen;
    final calendar = BuilderCalendarClient(
      CraftAiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response(
            '{"items":[],"nextCursor":"n","hasMore":false}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    await calendar.changes();
    await calendar.changes(cursor: '');
    expect(seen.url.queryParameters, isEmpty);
  });

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
