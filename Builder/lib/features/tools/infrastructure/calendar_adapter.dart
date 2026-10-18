import '../domain/tool_definition.dart';

/// Exception thrown when tool execution fails due to permissions or environment (F14-04).
class ToolExecutionException implements Exception {
  final String message;
  final OsPermissionStatus status;
  const ToolExecutionException(
    this.message, {
    this.status = OsPermissionStatus.denied,
  });
  @override
  String toString() => 'ToolExecutionException: $message ($status)';
}

/// Representation of a calendar event (F14-03).
class CalendarEvent {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final String? location;
  final String? notes;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.isAllDay = false,
    this.location,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'is_all_day': isAllDay,
      'location': location,
      'notes': notes,
    };
  }
}

/// Native calendar adapter interface and safe in-memory calendar for testing (F14-03, F14-13).
class CalendarAdapter {
  bool hasPermission;
  final List<CalendarEvent> _events = [];

  CalendarAdapter({
    bool hasPermission = true,
    OsPermissionStatus? permissionStatus,
  }) : hasPermission = permissionStatus != null
           ? permissionStatus == OsPermissionStatus.granted
           : hasPermission {
    // Seed test calendar with initial educational events (F14-13)
    final now = DateTime.now().toUtc();
    _events.addAll([
      CalendarEvent(
        id: 'evt_1',
        title: 'Урок математики 7Б',
        startTime: DateTime.utc(now.year, now.month, now.day, 9, 0),
        endTime: DateTime.utc(now.year, now.month, now.day, 9, 40),
        location: 'Кабинет 24',
      ),
      CalendarEvent(
        id: 'evt_2',
        title: 'Педсовет школы',
        startTime: DateTime.utc(now.year, now.month, now.day, 15, 0),
        endTime: DateTime.utc(now.year, now.month, now.day, 16, 0),
        location: 'Актовый зал',
      ),
    ]);
  }

  /// Reads events in the specified range.
  Future<List<CalendarEvent>> readEvents({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (!hasPermission) {
      throw const ToolExecutionException(
        'PERMISSION_DENIED: Доступ к календарю запрещён в настройках устройства',
        status: OsPermissionStatus.denied,
      );
    }

    return _events.where((evt) {
      return evt.startTime.isBefore(endDate) && evt.endTime.isAfter(startDate);
    }).toList();
  }

  /// Creates a new calendar event.
  Future<CalendarEvent> createEvent({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    bool isAllDay = false,
    String? location,
    String? notes,
  }) async {
    if (!hasPermission) {
      throw StateError(
        'PERMISSION_DENIED: Доступ к календарю запрещён в настройках устройства',
      );
    }

    final id = 'evt_${DateTime.now().millisecondsSinceEpoch}';
    final event = CalendarEvent(
      id: id,
      title: title.trim(),
      startTime: startTime,
      endTime: endTime,
      isAllDay: isAllDay,
      location: location?.trim(),
      notes: notes?.trim(),
    );

    _events.add(event);
    return event;
  }
}
