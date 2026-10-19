import 'package:builder/features/calendar/domain/calendar_models.dart';
import 'package:builder/features/calendar/domain/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEvent event({
  String id = 'e1',
  String title = 'Урок алгебры',
  String start = '2026-10-20T09:00:00',
  String end = '2026-10-20T09:45:00',
  String? zone = 'Asia/Almaty',
  bool allDay = false,
  List<int> reminders = const [15],
  CalendarRecurrence? recurrence,
}) => CalendarEvent(
  id: id,
  title: title,
  allDay: allDay,
  start: start,
  end: end,
  timeZone: allDay ? null : zone,
  reminders: reminders,
  recurrence: recurrence,
  version: 1,
);

List<PlannedReminder> plan(
  List<CalendarEvent> events, {
  DateTime? now,
  List<OccurrenceOverride> overrides = const [],
  bool kk = false,
}) => ReminderPlanner.plan(
  events: events,
  overrides: overrides,
  now: now ?? DateTime.utc(2026, 10, 19, 6),
  kk: kk,
);

void main() {
  test('fires at the event start in its own zone minus the lead time', () {
    // Almaty is UTC+5: 09:00 local is 04:00 UTC, 15 minutes earlier is 03:45.
    final result = plan([event()]);
    expect(result, hasLength(1));
    expect(result.single.fireAtUtc, DateTime.utc(2026, 10, 20, 3, 45));
    expect(result.single.title, 'Урок алгебры');
    expect(result.single.body, 'Через 15 мин · 09:00');
    expect(result.single.key, 'e1|2026-10-20|15');
  });

  test('a zero lead says the event is starting now, in Kazakh when asked', () {
    final result = plan([event(reminders: [0])], kk: true);
    expect(result.single.fireAtUtc, DateTime.utc(2026, 10, 20, 4));
    expect(result.single.body, 'Қазір басталады · 09:00');
  });

  test('the same input always yields the same ids, so rescheduling cannot duplicate', () {
    final first = plan([event(reminders: [0, 15, 60])]);
    final second = plan([event(reminders: [60, 15, 0])]);
    expect(first.map((r) => r.notificationId), second.map((r) => r.notificationId));
    expect(first.map((r) => r.notificationId).toSet(), hasLength(3));
    expect(first.every((r) => r.notificationId >= 0 && r.notificationId <= 0x7fffffff), isTrue);
    expect(plan([event(reminders: [15, 15])]), hasLength(1));
  });

  test('past reminders and reminders beyond 14 days are not planned', () {
    final now = DateTime.utc(2026, 10, 19, 6);
    expect(plan([event(start: '2026-10-19T09:00:00', end: '2026-10-19T09:30:00', reminders: [240])], now: now), isEmpty,
        reason: '05:00 local is 00:00 UTC, already past');
    expect(plan([event(start: '2026-11-05T09:00:00', end: '2026-11-05T10:00:00')], now: now), isEmpty);
    // Inside the horizon only because the reminder is days before a later event.
    final early = plan([event(start: '2026-11-02T09:00:00', end: '2026-11-02T10:00:00', reminders: [10080])], now: now);
    expect(early.single.fireAtUtc, DateTime.utc(2026, 10, 26, 4));
  });

  test('a daily series produces one reminder per day inside the window', () {
    final result = plan([
      event(
        recurrence: const CalendarRecurrence(frequency: 'daily'),
      ),
    ]);
    expect(result, hasLength(14));
    expect(result.first.key, 'e1|2026-10-20|15');
    expect(result.last.key, 'e1|2026-11-02|15');
    expect(result.map((r) => r.fireAtUtc), orderedEquals([...result.map((r) => r.fireAtUtc)]..sort()));
  });

  test('canceled occurrences are skipped and moved ones follow the new time', () {
    final series = event(recurrence: const CalendarRecurrence(frequency: 'daily'));
    final result = plan(
      [series],
      overrides: const [
        OccurrenceOverride(eventId: 'e1', date: '2026-10-21', canceled: true),
        OccurrenceOverride(
          eventId: 'e1',
          date: '2026-10-22',
          start: '2026-10-22T14:00:00',
          end: '2026-10-22T14:45:00',
        ),
      ],
    );
    expect(result.any((r) => r.key.contains('2026-10-21')), isFalse);
    final moved = result.singleWhere((r) => r.key.contains('2026-10-22'));
    expect(moved.fireAtUtc, DateTime.utc(2026, 10, 22, 8, 45));
    expect(moved.body, 'Через 15 мин · 14:00');
  });

  test('zone aliases the server accepts (UTC, old link names) are understood', () {
    expect(plan([event(zone: 'UTC')]).single.fireAtUtc, DateTime.utc(2026, 10, 20, 8, 45));
    expect(plan([event(zone: 'Europe/Kiev')]), hasLength(1));
  });

  test('events without reminders and events in an unknown zone are ignored, not fatal', () {
    expect(plan([event(reminders: const [])]), isEmpty);
    expect(plan([event(zone: 'Mars/Olympus')]), isEmpty);
    expect(plan([event(zone: null)]), isEmpty);
  });

  test('the spring-forward gap moves forward and the repeated hour takes the first pass', () {
    // Europe/Berlin: 2026-03-29 02:00 -> 03:00 (UTC+1 -> UTC+2); 2026-10-25 03:00 -> 02:00.
    final gap = ReminderPlanner.startInstant(
      CalendarOccurrence(
        eventId: 'e',
        occurrenceDate: '2026-03-29',
        title: 't',
        allDay: false,
        start: '2026-03-29T02:30:00',
        end: '2026-03-29T03:30:00',
        timeZone: 'Europe/Berlin',
      ),
    );
    expect(gap, DateTime.utc(2026, 3, 29, 1, 30), reason: '02:30 does not exist; read with the old offset it is 01:30 UTC = 03:30 local');
    final repeated = ReminderPlanner.startInstant(
      CalendarOccurrence(
        eventId: 'e',
        occurrenceDate: '2026-10-25',
        title: 't',
        allDay: false,
        start: '2026-10-25T02:30:00',
        end: '2026-10-25T03:30:00',
        timeZone: 'Europe/Berlin',
      ),
    );
    expect(repeated, DateTime.utc(2026, 10, 25, 0, 30), reason: 'first 02:30 is still summer time (UTC+2)');
  });

  test('an all-day event reminds at 09:00 device time on its day', () {
    final result = plan([
      event(
        allDay: true,
        start: '2026-10-21',
        end: '2026-10-21',
        reminders: [0],
      ),
    ]);
    expect(result.single.fireAtUtc, DateTime(2026, 10, 21, ReminderPlanner.allDayHour).toUtc());
    expect(result.single.body, 'Весь день · 2026-10-21');
  });

  test('no more than the nearest 50 reminders are kept', () {
    final many = [
      for (var i = 0; i < 70; i++)
        event(
          id: 'e$i',
          start: '2026-10-20T${(8 + i % 10).toString().padLeft(2, '0')}:${(i ~/ 10).toString().padLeft(2, '0')}:00',
          end: '2026-10-20T20:00:00',
        ),
    ];
    final result = plan(many);
    expect(result, hasLength(ReminderPlanner.maxPending));
    final all = [...result.map((r) => r.fireAtUtc)];
    expect(all, orderedEquals([...all]..sort()));
  });
}
