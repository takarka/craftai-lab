import 'package:builder/features/calendar/domain/calendar_models.dart';
import 'package:builder/features/calendar/domain/recurrence_expander.dart';
import 'package:flutter_test/flutter_test.dart';

// Parity cases with the server's CalendarRecurrenceTests (ai-sana).
DateTime d(String text) => RecurrenceExpander.parseDate(text);

CalendarRecurrence rule(
  String frequency, {
  int interval = 1,
  List<int> days = const [],
  String? until,
  int? count,
  List<String> excluded = const [],
}) => CalendarRecurrence(
  frequency: frequency,
  interval: interval,
  byWeekday: days,
  until: until,
  count: count,
  excludedDates: excluded,
);

List<String> expand(
  String start,
  CalendarRecurrence? r,
  String from,
  String to,
) => RecurrenceExpander.expandDates(
  d(start),
  r,
  d(from),
  d(to),
).map(RecurrenceExpander.formatDate).toList();

CalendarEvent event({
  String id = 'e1',
  String start = '2026-10-19T09:00:00',
  String end = '2026-10-19T09:45:00',
  bool allDay = false,
  CalendarRecurrence? recurrence,
}) => CalendarEvent(
  id: id,
  title: 'Урок',
  allDay: allDay,
  start: start,
  end: end,
  timeZone: allDay ? null : 'Asia/Almaty',
  recurrence: recurrence,
  version: 1,
);

void main() {
  group('expandDates matches the server', () {
    test('no rule returns the start only inside the range', () {
      expect(expand('2026-10-19', null, '2026-10-19', '2026-10-19'), ['2026-10-19']);
      expect(expand('2026-10-19', null, '2026-10-20', '2026-10-30'), isEmpty);
    });

    test('daily interval skips days and keeps alignment for a later range', () {
      final r = rule('daily', interval: 3);
      expect(expand('2026-10-01', r, '2026-10-01', '2026-10-12'), [
        '2026-10-01', '2026-10-04', '2026-10-07', '2026-10-10',
      ]);
      expect(expand('2026-10-01', r, '2026-10-05', '2026-10-12'), [
        '2026-10-07', '2026-10-10',
      ]);
    });

    test('count includes excluded dates; until is inclusive', () {
      expect(
        expand('2026-10-01', rule('daily', count: 4, excluded: ['2026-10-02']), '2026-10-01', '2026-10-31'),
        ['2026-10-01', '2026-10-03', '2026-10-04'],
      );
      expect(
        expand('2026-10-01', rule('daily', until: '2026-10-03'), '2026-10-01', '2026-10-31'),
        ['2026-10-01', '2026-10-02', '2026-10-03'],
      );
    });

    test('weekly defaults to the start weekday', () {
      expect(expand('2026-10-19', rule('weekly'), '2026-10-19', '2026-11-09'), [
        '2026-10-19', '2026-10-26', '2026-11-02', '2026-11-09',
      ]);
    });

    test('weekly never emits dates before the series start', () {
      final r = rule('weekly', days: [DateTime.monday, DateTime.wednesday]);
      expect(expand('2026-10-21', r, '2026-10-19', '2026-10-28'), [
        '2026-10-21', '2026-10-26', '2026-10-28',
      ]);
    });

    test('weekly interval skips weeks', () {
      expect(
        expand('2026-10-19', rule('weekly', interval: 2), '2026-10-19', '2026-11-30'),
        ['2026-10-19', '2026-11-02', '2026-11-16', '2026-11-30'],
      );
    });

    test('weekly count spans weekdays', () {
      final r = rule('weekly', days: [DateTime.monday, DateTime.friday], count: 3);
      expect(expand('2026-10-19', r, '2026-10-01', '2026-12-31'), [
        '2026-10-19', '2026-10-23', '2026-10-26',
      ]);
    });

    test('weekly range far from the start finds the right date', () {
      expect(expand('2024-01-01', rule('weekly'), '2026-10-19', '2026-10-25'), ['2026-10-19']);
    });

    test('excluded dates are skipped; reversed range is empty', () {
      expect(
        expand('2026-10-19', rule('weekly', excluded: ['2026-10-26']), '2026-10-19', '2026-11-02'),
        ['2026-10-19', '2026-11-02'],
      );
      expect(expand('2026-10-19', rule('daily'), '2026-10-25', '2026-10-19'), isEmpty);
    });
  });

  group('occurrences', () {
    test('keeps wall-clock time and span across the DST change', () {
      // Europe/Berlin changes on 2026-03-29; the local 09:00 must not move.
      final items = RecurrenceExpander.occurrences(
        [event(start: '2026-03-23T09:00:00', end: '2026-03-23T09:45:00', recurrence: rule('weekly'))],
        '2026-03-23',
        '2026-04-05',
        const [],
      );
      expect(items.map((o) => o.start), [
        '2026-03-23T09:00:00', '2026-03-30T09:00:00',
      ]);
      expect(items.every((o) => o.end.endsWith('T09:45:00')), isTrue);
      expect(items.first.startUtc, isNull, reason: 'UTC needs an IANA database');
    });

    test('canceled and moved occurrences follow the overrides', () {
      final items = RecurrenceExpander.occurrences(
        [event(recurrence: rule('weekly'))],
        '2026-10-19',
        '2026-11-02',
        const [
          OccurrenceOverride(eventId: 'e1', date: '2026-10-26', canceled: true),
          OccurrenceOverride(
            eventId: 'e1',
            date: '2026-11-02',
            title: 'Перенос',
            start: '2026-11-02T14:00:00',
            end: '2026-11-02T14:45:00',
          ),
        ],
      );
      expect(items.map((o) => o.occurrenceDate), ['2026-10-19', '2026-11-02']);
      expect(items.last.title, 'Перенос');
      expect(items.last.start, '2026-11-02T14:00:00');
      expect(items.last.isOverride, isTrue);
    });

    test('multi-day event is listed on a range starting inside it', () {
      final items = RecurrenceExpander.occurrences(
        [event(allDay: true, start: '2026-10-19', end: '2026-10-21')],
        '2026-10-20',
        '2026-10-25',
        const [],
      );
      expect(items, hasLength(1));
      expect(items.single.start, '2026-10-19');
      expect(items.single.timeZone, isNull);
    });

    test('events outside the range are omitted; order is start then title', () {
      final items = RecurrenceExpander.occurrences(
        [
          event(id: 'late', start: '2026-10-20T15:00:00', end: '2026-10-20T16:00:00'),
          event(id: 'early', start: '2026-10-20T08:00:00', end: '2026-10-20T09:00:00'),
          event(id: 'out', start: '2026-11-20T08:00:00', end: '2026-11-20T09:00:00'),
        ],
        '2026-10-01',
        '2026-10-31',
        const [],
      );
      expect(items.map((o) => o.eventId), ['early', 'late']);
    });
  });

  group('reconcile', () {
    test('learns canceled, moved and plain dates from a server answer', () {
      final events = [event(recurrence: rule('weekly'))];
      CalendarOccurrence served(String date, {bool over = false, String? start}) =>
          CalendarOccurrence(
            eventId: 'e1',
            occurrenceDate: date,
            title: over ? 'Другое' : 'Урок',
            allDay: false,
            start: start ?? '${date}T09:00:00',
            end: start == null ? '${date}T09:45:00' : '${date}T15:00:00',
            isOverride: over,
          );
      final result = RecurrenceExpander.reconcile(events, '2026-10-19', '2026-11-02', [
        served('2026-10-19'),
        // 2026-10-26 omitted by the server: canceled.
        served('2026-11-02', over: true, start: '2026-11-02T14:00:00'),
      ]);
      expect(result.clearKeys, ['e1|2026-10-19']);
      final canceled = result.set.firstWhere((o) => o.date == '2026-10-26');
      expect(canceled.canceled, isTrue);
      final moved = result.set.firstWhere((o) => o.date == '2026-11-02');
      expect(moved.start, '2026-11-02T14:00:00');
      expect(moved.title, 'Другое');
    });
  });
}
