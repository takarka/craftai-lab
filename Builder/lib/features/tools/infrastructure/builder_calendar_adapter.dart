import '../../calendar/application/calendar_sync_service.dart';
import '../../calendar/domain/calendar_models.dart';
import '../../calendar/domain/recurrence_expander.dart';
import '../../calendar/infrastructure/builder_calendar_client.dart';
import '../../calendar/infrastructure/calendar_repository.dart';

/// Thrown when a calendar tool cannot run; never replaced by sample data.
class ToolExecutionException implements Exception {
  const ToolExecutionException(this.message);
  final String message;
  @override
  String toString() => 'ToolExecutionException: $message';
}

/// Calendar tools backed by the server calendar through the owner-scoped
/// cache. Times are wall-clock values plus an IANA zone, as on the server.
class BuilderCalendarAdapter {
  const BuilderCalendarAdapter({
    required this.repository,
    this.client,
    this.onEventSaved,
  });
  final CalendarRepository repository;
  final BuilderCalendarClient? client;

  /// Called after a create reached the server, so phone reminders follow it.
  final Future<void> Function(String ownerId)? onEventSaved;

  /// A model run receives at most this many occurrences.
  static const maxEvents = 100;
  static const _maxRangeDays = 62;

  Future<Map<String, dynamic>> read(
    String ownerId, {
    required String startDate,
    required String endDate,
  }) async {
    final from = startDate.substring(0, 10);
    var to = endDate.substring(0, 10);
    final fromDay = RecurrenceExpander.parseDate(from);
    var toDay = RecurrenceExpander.parseDate(to);
    if (toDay.isBefore(fromDay)) {
      throw const ToolExecutionException('end_date раньше start_date.');
    }
    var truncatedRange = false;
    final lastAllowed = fromDay.add(const Duration(days: _maxRangeDays - 1));
    if (toDay.isAfter(lastAllowed)) {
      toDay = lastAllowed;
      to = RecurrenceExpander.formatDate(toDay);
      truncatedRange = true;
    }

    final api = client;
    if (api != null) {
      try {
        final service = CalendarSyncService(client: api, repository: repository);
        await service.sync(ownerId);
        await service.refreshRange(ownerId, from, to);
      } catch (_) {
        // Fall back to the cache below unless it was never filled.
      }
    }
    if (await repository.syncedAt(ownerId) == null) {
      throw const ToolExecutionException(
        'Календарь Builder недоступен: нет соединения и нет сохранённой копии.',
      );
    }

    final all = RecurrenceExpander.occurrences(
      await repository.events(ownerId),
      from,
      to,
      await repository.overrides(ownerId),
    );
    final shown = all.take(maxEvents).toList();
    return {
      'from': from,
      'to': to,
      'events': [
        for (final o in shown)
          {
            'title': o.title,
            'start': o.start,
            'end': o.end,
            'all_day': o.allDay,
            if (o.timeZone != null) 'time_zone': o.timeZone,
            if (o.notes != null && o.notes!.isNotEmpty) 'notes': o.notes,
          },
      ],
      'count': shown.length,
      if (all.length > shown.length || truncatedRange) 'truncated': true,
    };
  }

  /// Creates after teacher confirmation. An unknown outcome is queued and
  /// replayed with the same key, so a retry never duplicates the event.
  Future<Map<String, dynamic>> create(
    String ownerId, {
    required String title,
    required String start,
    required String end,
    String? timeZone,
    bool allDay = false,
    String? notes,
    List<int> reminderMinutes = const [],
  }) async {
    final api = client;
    if (api == null) {
      throw const ToolExecutionException('Календарь Builder недоступен: нет входа в аккаунт.');
    }
    if (!allDay && (timeZone == null || timeZone.isEmpty)) {
      throw const ToolExecutionException('Нужен часовой пояс IANA (time_zone), например Asia/Almaty.');
    }
    final event = CalendarEvent(
      id: '',
      version: 0,
      title: title.trim(),
      notes: notes,
      allDay: allDay,
      start: allDay ? start.substring(0, 10) : start.substring(0, 19),
      end: allDay ? end.substring(0, 10) : end.substring(0, 19),
      timeZone: allDay ? null : timeZone,
      reminders: ({...reminderMinutes}.toList()..sort()),
    );
    final outcome = await CalendarSyncService(client: api, repository: repository)
        .create(ownerId, event.toInputJson());
    if (outcome == CalendarCreateOutcome.saved) {
      try {
        await onEventSaved?.call(ownerId);
      } catch (_) {
        // The event is saved; reminders are rebuilt on the next sync.
      }
    }
    return switch (outcome) {
      CalendarCreateOutcome.saved => {'status': 'saved', 'message': 'Событие «$title» сохранено на сервере'},
      CalendarCreateOutcome.queued => {
        'status': 'queued',
        'message': 'Ответа сервера нет: событие «$title» отправится повторно без дублей',
      },
      CalendarCreateOutcome.rejected => throw const ToolExecutionException('Сервер отклонил событие. Проверьте даты и часовой пояс.'),
      CalendarCreateOutcome.authRequired => throw const ToolExecutionException('Нужно заново войти в аккаунт.'),
    };
  }
}
