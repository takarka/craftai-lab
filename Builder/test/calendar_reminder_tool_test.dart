import 'dart:convert';

import 'package:builder/features/calendar/infrastructure/builder_calendar_client.dart';
import 'package:builder/features/calendar/infrastructure/calendar_repository.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:builder/features/tools/domain/tools_registry.dart';
import 'package:builder/features/tools/infrastructure/builder_calendar_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> args([Object? reminders]) => {
  'title': 'Консультация',
  'start_time': '2026-10-20T09:00:00',
  'end_time': '2026-10-20T09:45:00',
  'time_zone': 'Asia/Almaty',
  if (reminders != null) 'reminder_minutes': reminders,
};

void main() {
  final tool = ToolsRegistry.allTools.firstWhere((t) => t.name == ToolsRegistry.createCalendarEvent);

  group('reminder_minutes of create_calendar_event', () {
    test('accepts up to three lead times within the contract range', () {
      expect(tool.validateArguments(args()), isEmpty);
      expect(tool.validateArguments(args([0, 15, 10080])), isEmpty);
    });

    test('rejects too many, out-of-range and non-integer values', () {
      expect(tool.validateArguments(args([1, 2, 3, 4])), isNotEmpty);
      expect(tool.validateArguments(args([-1])), isNotEmpty);
      expect(tool.validateArguments(args([10081])), isNotEmpty);
      expect(tool.validateArguments(args(['15'])), isNotEmpty);
      expect(tool.validateArguments(args(15)), isNotEmpty);
    });
  });

  test('the confirmed event is sent with sorted, unique reminders', () async {
    Map<String, dynamic>? sent;
    final api = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'id': 'e1',
          'version': 1,
          ...sent!,
        }),
        201,
        headers: {'content-type': 'application/json'},
      );
    });
    var saved = 0;
    final adapter = BuilderCalendarAdapter(
      repository: InMemoryCalendarRepository(),
      client: BuilderCalendarClient(
        CraftAiClient(baseUri: Uri.parse('https://api.example.test'), httpClient: api),
      ),
      onEventSaved: (_) async => saved++,
    );

    final result = await adapter.create(
      'a',
      title: 'Консультация',
      start: '2026-10-20T09:00:00',
      end: '2026-10-20T09:45:00',
      timeZone: 'Asia/Almaty',
      reminderMinutes: const [60, 15, 15],
    );

    expect(result['status'], 'saved');
    expect(sent!['reminders'], [15, 60]);
    expect(saved, 1, reason: 'the phone schedule is rebuilt once the event exists');
  });
}
