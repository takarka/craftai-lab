/// Wire models for the Builder calendar (EB-06 contract). Times are wall-clock
/// strings (`yyyy-MM-ddTHH:mm:ss`, or `yyyy-MM-dd` for all-day events) plus an
/// IANA zone; nothing here converts through the device time zone.
library;

const calendarWeekdayNames = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// `DateTime.weekday` (1 = Monday) for a contract weekday name.
int weekdayNumber(String name) {
  final index = calendarWeekdayNames.indexOf(name);
  if (index < 0) throw FormatException('Unknown weekday: $name');
  return index + 1;
}

String weekdayName(int number) => calendarWeekdayNames[number - 1];

class CalendarRecurrence {
  const CalendarRecurrence({
    required this.frequency,
    this.interval = 1,
    this.byWeekday = const [],
    this.until,
    this.count,
    this.excludedDates = const [],
  });

  static const daily = 'daily';
  static const weekly = 'weekly';

  final String frequency;
  final int interval;

  /// `DateTime.weekday` numbers (1 = Monday ... 7 = Sunday).
  final List<int> byWeekday;
  final String? until;
  final int? count;
  final List<String> excludedDates;

  factory CalendarRecurrence.fromJson(Map<String, dynamic> json) =>
      CalendarRecurrence(
        frequency: json['frequency'] as String,
        interval: json['interval'] as int? ?? 1,
        byWeekday: [
          for (final name in (json['byWeekday'] as List?) ?? const [])
            weekdayNumber(name as String),
        ],
        until: json['until'] as String?,
        count: json['count'] as int?,
        excludedDates: [
          for (final date in (json['excludedDates'] as List?) ?? const [])
            date as String,
        ],
      );

  Map<String, dynamic> toJson() => {
    'frequency': frequency,
    'interval': interval,
    if (byWeekday.isNotEmpty) 'byWeekday': byWeekday.map(weekdayName).toList(),
    if (until != null) 'until': until,
    if (count != null) 'count': count,
    if (excludedDates.isNotEmpty) 'excludedDates': excludedDates,
  };

  CalendarRecurrence copyWith({
    String? frequency,
    int? interval,
    List<int>? byWeekday,
    String? until,
    int? count,
    bool clearEnd = false,
    List<String>? excludedDates,
  }) => CalendarRecurrence(
    frequency: frequency ?? this.frequency,
    interval: interval ?? this.interval,
    byWeekday: byWeekday ?? this.byWeekday,
    until: clearEnd ? null : until ?? this.until,
    count: clearEnd ? null : count ?? this.count,
    excludedDates: excludedDates ?? this.excludedDates,
  );
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    this.notes,
    required this.allDay,
    required this.start,
    required this.end,
    this.timeZone,
    this.recurrence,
    this.reminders = const [],
    this.subject,
    this.grade,
    required this.version,
    this.createdAtUtc,
    this.updatedAtUtc,
  });

  final String id;
  final String title;
  final String? notes;
  final bool allDay;
  final String start;
  final String end;
  final String? timeZone;
  final CalendarRecurrence? recurrence;
  final List<int> reminders;
  final String? subject;
  final int? grade;
  final int version;
  final String? createdAtUtc;
  final String? updatedAtUtc;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
    id: json['id'] as String,
    title: json['title'] as String,
    notes: json['notes'] as String?,
    allDay: json['allDay'] as bool,
    start: json['start'] as String,
    end: json['end'] as String,
    timeZone: json['timeZone'] as String?,
    recurrence: json['recurrence'] == null
        ? null
        : CalendarRecurrence.fromJson(
            Map<String, dynamic>.from(json['recurrence'] as Map),
          ),
    reminders: [
      for (final value in (json['reminders'] as List?) ?? const [])
        value as int,
    ],
    subject: json['subject'] as String?,
    grade: json['grade'] as int?,
    version: json['version'] as int,
    createdAtUtc: json['createdAtUtc'] as String?,
    updatedAtUtc: json['updatedAtUtc'] as String?,
  );

  /// Request body for create/replace; the server owns id, version and stamps.
  Map<String, dynamic> toInputJson() => {
    'title': title,
    if (notes != null) 'notes': notes,
    'allDay': allDay,
    'start': start,
    'end': end,
    if (!allDay && timeZone != null) 'timeZone': timeZone,
    if (recurrence != null) 'recurrence': recurrence!.toJson(),
    'reminders': reminders,
    if (subject != null) 'subject': subject,
    if (grade != null) 'grade': grade,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    if (createdAtUtc != null) 'createdAtUtc': createdAtUtc,
    if (updatedAtUtc != null) 'updatedAtUtc': updatedAtUtc,
    ...toInputJson(),
  };
}

class CalendarOccurrence {
  const CalendarOccurrence({
    required this.eventId,
    required this.occurrenceDate,
    required this.title,
    this.notes,
    required this.allDay,
    required this.start,
    required this.end,
    this.timeZone,
    this.startUtc,
    this.endUtc,
    this.isOverride = false,
    this.reminders = const [],
  });

  final String eventId;
  final String occurrenceDate;
  final String title;
  final String? notes;
  final bool allDay;
  final String start;
  final String end;
  final String? timeZone;
  final String? startUtc;
  final String? endUtc;
  final bool isOverride;
  final List<int> reminders;

  /// Calendar day the occurrence starts on.
  String get startDate => start.substring(0, 10);

  factory CalendarOccurrence.fromJson(Map<String, dynamic> json) =>
      CalendarOccurrence(
        eventId: json['eventId'] as String,
        occurrenceDate: json['occurrenceDate'] as String,
        title: json['title'] as String,
        notes: json['notes'] as String?,
        allDay: json['allDay'] as bool,
        start: json['start'] as String,
        end: json['end'] as String,
        timeZone: json['timeZone'] as String?,
        startUtc: json['startUtc'] as String?,
        endUtc: json['endUtc'] as String?,
        isOverride: json['isOverride'] as bool? ?? false,
        reminders: [
          for (final value in (json['reminders'] as List?) ?? const [])
            value as int,
        ],
      );
}

/// Per-occurrence deviation from the series, learned from server responses.
class OccurrenceOverride {
  const OccurrenceOverride({
    required this.eventId,
    required this.date,
    this.canceled = false,
    this.title,
    this.notes,
    this.start,
    this.end,
  });

  final String eventId;
  final String date;
  final bool canceled;
  final String? title;
  final String? notes;
  final String? start;
  final String? end;

  factory OccurrenceOverride.fromMap(Map<String, Object?> row) =>
      OccurrenceOverride(
        eventId: row['event_id'] as String,
        date: row['occurrence_date'] as String,
        canceled: (row['canceled'] as int) == 1,
        title: row['title'] as String?,
        notes: row['notes'] as String?,
        start: row['start_local'] as String?,
        end: row['end_local'] as String?,
      );
}

class CalendarChange {
  const CalendarChange({required this.eventId, this.event});
  final String eventId;

  /// Null for a tombstone (`type: delete`).
  final CalendarEvent? event;
  bool get isDelete => event == null;

  factory CalendarChange.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final eventId = json['eventId'] as String;
    if (type == 'delete') return CalendarChange(eventId: eventId);
    if (type != 'upsert' || json['event'] == null) {
      throw FormatException('Invalid calendar change: $type');
    }
    return CalendarChange(
      eventId: eventId,
      event: CalendarEvent.fromJson(
        Map<String, dynamic>.from(json['event'] as Map),
      ),
    );
  }
}

class CalendarChangesPage {
  const CalendarChangesPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });
  final List<CalendarChange> items;
  final String nextCursor;
  final bool hasMore;

  factory CalendarChangesPage.fromJson(Map<String, dynamic> json) =>
      CalendarChangesPage(
        items: [
          for (final item in json['items'] as List)
            CalendarChange.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        nextCursor: json['nextCursor'] as String,
        hasMore: json['hasMore'] as bool,
      );
}

/// Create submission whose outcome may be unknown; replayed with the same key.
class PendingCalendarCreate {
  const PendingCalendarCreate({
    required this.key,
    required this.input,
    required this.createdAtUtc,
  });
  final String key;
  final Map<String, dynamic> input;
  final String createdAtUtc;
}
