import 'calendar_models.dart';

/// Port of the server's `RecurrenceExpander` and occurrence building
/// (`ai-sana` Builder/Calendar). It works on wall-clock dates only: the
/// UTC instants (`startUtc`/`endUtc`) need an IANA database and are not
/// produced offline.
///
/// Dates are `yyyy-MM-dd` strings; arithmetic uses UTC midnights so device DST
/// never shifts a day.
abstract final class RecurrenceExpander {
  static const _iterationGuard = 100000;
  static const _msPerDay = 86400000;

  static DateTime parseDate(String value) =>
      DateTime.parse('${value.substring(0, 10)}T00:00:00Z');

  static String formatDate(DateTime value) =>
      value.toIso8601String().substring(0, 10);

  static int _dayNumber(DateTime value) =>
      value.millisecondsSinceEpoch ~/ _msPerDay;

  static DateTime _addDays(DateTime value, int days) =>
      value.add(Duration(days: days));

  static int _mondayOffset(DateTime value) => value.weekday - 1;

  /// Start dates of occurrences within `[from, to]`. Excluded dates are
  /// skipped but still count towards `count`, like EXDATE in RFC 5545.
  static List<DateTime> expandDates(
    DateTime start,
    CalendarRecurrence? rule,
    DateTime from,
    DateTime to,
  ) {
    final result = <DateTime>[];
    if (to.isBefore(from)) return result;
    if (rule == null) {
      if (!start.isBefore(from) && !start.isAfter(to)) result.add(start);
      return result;
    }

    final excluded = rule.excludedDates.toSet();
    final until = rule.until == null ? null : parseDate(rule.until!);
    var guard = 0;

    if (rule.frequency == CalendarRecurrence.daily) {
      var firstIndex = 0;
      if (from.isAfter(start)) {
        final gap = _dayNumber(from) - _dayNumber(start);
        firstIndex = (gap + rule.interval - 1) ~/ rule.interval;
      }
      for (var index = firstIndex; guard++ < _iterationGuard; index++) {
        if (rule.count != null && index >= rule.count!) break;
        final date = _addDays(start, index * rule.interval);
        if (date.isAfter(to) || (until != null && date.isAfter(until))) break;
        if (!date.isBefore(from) && !excluded.contains(formatDate(date))) {
          result.add(date);
        }
      }
      return result;
    }

    final weekdayOffsets = <int>{
      for (final day in rule.byWeekday.isEmpty
          ? [start.weekday]
          : rule.byWeekday)
        day - 1,
    }.toList()..sort();
    final weekStart = _addDays(start, -_mondayOffset(start));
    final stride = 7 * rule.interval;

    var firstWeek = 0;
    if (rule.count == null && from.isAfter(weekStart)) {
      final weeks = (_dayNumber(from) - _dayNumber(weekStart)) ~/ stride - 1;
      firstWeek = weeks < 0 ? 0 : weeks;
    }

    // The occurrence number matters only with `count`, where no weeks are skipped.
    var occurrence = 0;
    for (var week = firstWeek; guard++ < _iterationGuard; week++) {
      final weekBase = _addDays(weekStart, week * stride);
      if (weekBase.isAfter(to)) break;
      for (final offset in weekdayOffsets) {
        final date = _addDays(weekBase, offset);
        if (date.isBefore(start)) continue;
        if (rule.count != null && occurrence >= rule.count!) return result;
        occurrence++;
        if (date.isAfter(to) || (until != null && date.isAfter(until))) {
          return result;
        }
        if (!date.isBefore(from) && !excluded.contains(formatDate(date))) {
          result.add(date);
        }
      }
    }
    return result;
  }

  static DateTime _local(String value, bool allDay) => allDay
      ? parseDate(value)
      : DateTime.parse('${value.substring(0, 19)}Z');

  static String _formatLocal(DateTime value, bool allDay) => allDay
      ? formatDate(value)
      : value.toIso8601String().substring(0, 19);

  /// Occurrences of [events] intersecting `[from, to]` (dates), with the
  /// known [overrides] applied, ordered by start then title (ordinal).
  static List<CalendarOccurrence> occurrences(
    Iterable<CalendarEvent> events,
    String from,
    String to,
    Iterable<OccurrenceOverride> overrides,
  ) {
    final fromDate = parseDate(from);
    final toDate = parseDate(to);
    final byKey = {for (final o in overrides) '${o.eventId}|${o.date}': o};
    final items = <(DateTime, CalendarOccurrence)>[];

    for (final event in events) {
      final startLocal = _local(event.start, event.allDay);
      final endLocal = _local(event.end, event.allDay);
      final startDate = parseDate(event.start);
      final spanDays = _dayNumber(parseDate(event.end)) - _dayNumber(startDate);
      if (event.recurrence == null &&
          (!startDate.isBefore(toDate.add(const Duration(days: 1))) ||
              parseDate(event.end).isBefore(fromDate))) {
        continue;
      }
      for (final date in expandDates(
        startDate,
        event.recurrence,
        _addDays(fromDate, -spanDays),
        toDate,
      )) {
        final key = '${event.id}|${formatDate(date)}';
        final over = byKey[key];
        if (over != null && over.canceled) continue;
        final occurrence = build(event, date, over, startLocal, endLocal);
        if (parseDate(occurrence.end).isBefore(fromDate)) continue;
        items.add((_local(occurrence.start, event.allDay), occurrence));
      }
    }

    items.sort((a, b) {
      final byStart = a.$1.compareTo(b.$1);
      return byStart != 0 ? byStart : a.$2.title.compareTo(b.$2.title);
    });
    return [for (final item in items) item.$2];
  }

  static CalendarOccurrence build(
    CalendarEvent event,
    DateTime date,
    OccurrenceOverride? over,
    DateTime startLocal,
    DateTime endLocal,
  ) {
    final String start;
    final String end;
    if (over?.start != null && over?.end != null) {
      start = over!.start!;
      end = over.end!;
    } else {
      final span = endLocal.difference(startLocal);
      final occurrenceStart = DateTime.utc(
        date.year,
        date.month,
        date.day,
        startLocal.hour,
        startLocal.minute,
        startLocal.second,
      );
      start = _formatLocal(occurrenceStart, event.allDay);
      end = _formatLocal(occurrenceStart.add(span), event.allDay);
    }
    return CalendarOccurrence(
      eventId: event.id,
      occurrenceDate: formatDate(date),
      title: over?.title ?? event.title,
      notes: over?.notes ?? event.notes,
      allDay: event.allDay,
      start: start,
      end: end,
      timeZone: event.allDay ? null : event.timeZone,
      isOverride: over != null,
      reminders: event.reminders,
    );
  }

  /// Derives the overrides in `[from, to]` from a server answer: a series
  /// date the server omitted was canceled, an `isOverride` item carries the
  /// changed fields, a plain item has no override.
  static ({List<OccurrenceOverride> set, List<String> clearKeys}) reconcile(
    Iterable<CalendarEvent> events,
    String from,
    String to,
    Iterable<CalendarOccurrence> served,
  ) {
    final servedByKey = {for (final o in served) '${o.eventId}|${o.occurrenceDate}': o};
    final set = <OccurrenceOverride>[];
    final clear = <String>[];
    final fromDate = parseDate(from);
    final toDate = parseDate(to);
    for (final event in events) {
      final startDate = parseDate(event.start);
      final spanDays =
          _dayNumber(parseDate(event.end)) - _dayNumber(startDate);
      for (final date in expandDates(
        startDate,
        event.recurrence,
        _addDays(fromDate, -spanDays),
        toDate,
      )) {
        final date0 = formatDate(date);
        final key = '${event.id}|$date0';
        final item = servedByKey[key];
        if (item == null) {
          set.add(OccurrenceOverride(eventId: event.id, date: date0, canceled: true));
        } else if (item.isOverride) {
          set.add(
            OccurrenceOverride(
              eventId: event.id,
              date: date0,
              title: item.title,
              notes: item.notes,
              start: item.start,
              end: item.end,
            ),
          );
        } else {
          clear.add(key);
        }
      }
    }
    return (set: set, clearKeys: clear);
  }
}
