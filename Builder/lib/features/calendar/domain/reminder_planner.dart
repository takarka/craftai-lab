import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'calendar_models.dart';
import 'recurrence_expander.dart';

/// One local notification the device should hold for a calendar occurrence.
class PlannedReminder {
  const PlannedReminder({
    required this.key,
    required this.notificationId,
    required this.fireAtUtc,
    required this.title,
    required this.body,
  });

  /// `eventId|occurrenceDate|minutesBefore`; the same reminder always has the same key.
  final String key;

  /// Stable 31-bit id derived from [key], so planning twice replaces instead of duplicating.
  final int notificationId;
  final DateTime fireAtUtc;
  final String title;
  final String body;

  static const payloadPrefix = 'calendar-reminder:';
  String get payload => '$payloadPrefix$key';
}

/// Turns cached events into the reminders to schedule. Pure: no platform calls.
abstract final class ReminderPlanner {
  /// How far ahead reminders are scheduled; the plan is rebuilt whenever the app syncs.
  static const horizon = Duration(days: 14);

  /// iOS keeps only the 64 nearest pending notifications, so stay below that.
  static const maxPending = 50;

  /// Reminders of an all-day event are anchored to this local hour of the day.
  static const allDayHour = 9;

  /// Longest `minutesBefore` the contract allows (7 days).
  static const _maxLeadDays = 7;

  static bool _zonesReady = false;

  static void ensureTimeZones() {
    if (_zonesReady) return;
    tzdata.initializeTimeZones();
    _zonesReady = true;
  }

  /// FNV-1a, masked to the positive 31-bit range notification ids need.
  static int idFor(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${_two(value.month)}-${_two(value.day)}';

  /// The instant a timed occurrence starts, or null when its zone is unknown.
  /// A skipped local time (spring forward) moves forward; a repeated one
  /// (fall back) takes the first occurrence, as the server does.
  static DateTime? startInstant(CalendarOccurrence occurrence) {
    final zone = occurrence.timeZone;
    if (zone == null || zone.isEmpty) return null;
    final tz.Location location;
    try {
      ensureTimeZones();
      location = tz.getLocation(zone);
    } on Object {
      return null;
    }
    final wall = DateTime.parse('${occurrence.start.substring(0, 19)}Z');
    final wallMs = wall.millisecondsSinceEpoch;
    // The offsets in force a day before and after bracket any transition.
    final before = location.timeZone(wallMs - Duration.millisecondsPerDay).offset.inMilliseconds;
    final after = location.timeZone(wallMs + Duration.millisecondsPerDay).offset.inMilliseconds;
    final valid = <int>[
      for (final offset in {before, after})
        if (location.timeZone(wallMs - offset).offset.inMilliseconds == offset) wallMs - offset,
    ]..sort();
    // No valid reading means the local time was skipped: use the old offset,
    // which lands after the gap. Two readings mean it repeats: take the first.
    final instant = valid.isEmpty ? wallMs - before : valid.first;
    return DateTime.fromMillisecondsSinceEpoch(instant, isUtc: true);
  }

  static DateTime _allDayInstant(CalendarOccurrence occurrence) {
    final day = RecurrenceExpander.parseDate(occurrence.start);
    return DateTime(day.year, day.month, day.day, allDayHour).toUtc();
  }

  static String _timeLabel(CalendarOccurrence occurrence, bool kk) {
    if (occurrence.allDay) return kk ? 'Күні бойы' : 'Весь день';
    return occurrence.start.substring(11, 16);
  }

  static String _body(CalendarOccurrence occurrence, int minutes, bool kk) {
    final time = _timeLabel(occurrence, kk);
    if (occurrence.allDay) return '$time · ${occurrence.startDate}';
    if (minutes == 0) {
      return kk ? 'Қазір басталады · $time' : 'Начинается сейчас · $time';
    }
    final left = _duration(minutes, kk);
    return kk ? '$left қалды · $time' : 'Через $left · $time';
  }

  static String _duration(int minutes, bool kk) {
    if (minutes % 1440 == 0) return '${minutes ~/ 1440} ${kk ? 'күн' : 'дн'}';
    if (minutes % 60 == 0) return '${minutes ~/ 60} ${kk ? 'сағ' : 'ч'}';
    return '$minutes мин';
  }

  /// Reminders that fire in `(now, now + horizon]`, soonest first, one per
  /// `(event, date, minutes)`.
  static List<PlannedReminder> plan({
    required Iterable<CalendarEvent> events,
    required Iterable<OccurrenceOverride> overrides,
    required DateTime now,
    bool kk = false,
  }) {
    final nowUtc = now.toUtc();
    final until = nowUtc.add(horizon);
    // A reminder up to a week early belongs to an occurrence up to a week
    // beyond the horizon; start a day early for zone offsets.
    final from = _date(nowUtc.subtract(const Duration(days: 1)));
    final to = _date(until.add(const Duration(days: _maxLeadDays + 1)));
    final occurrences = RecurrenceExpander.occurrences(
      events.where((e) => e.reminders.isNotEmpty),
      from,
      to,
      overrides,
    );

    final seen = <String>{};
    final usedIds = <int>{};
    final planned = <PlannedReminder>[];
    for (final occurrence in occurrences) {
      final start = occurrence.allDay
          ? _allDayInstant(occurrence)
          : startInstant(occurrence);
      if (start == null) continue;
      for (final minutes in occurrence.reminders.toSet()) {
        final fireAt = start.subtract(Duration(minutes: minutes));
        if (!fireAt.isAfter(nowUtc) || fireAt.isAfter(until)) continue;
        final key = '${occurrence.eventId}|${occurrence.occurrenceDate}|$minutes';
        final id = idFor(key);
        if (!seen.add(key) || !usedIds.add(id)) continue;
        planned.add(
          PlannedReminder(
            key: key,
            notificationId: id,
            fireAtUtc: fireAt,
            title: occurrence.title,
            body: _body(occurrence, minutes, kk),
          ),
        );
      }
    }
    planned.sort((a, b) {
      final byTime = a.fireAtUtc.compareTo(b.fireAtUtc);
      return byTime != 0 ? byTime : a.key.compareTo(b.key);
    });
    return planned.length <= maxPending ? planned : planned.sublist(0, maxPending);
  }
}
