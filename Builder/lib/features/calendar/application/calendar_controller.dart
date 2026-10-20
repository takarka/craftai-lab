import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/infrastructure/craft_ai_client.dart';
import '../domain/calendar_models.dart';
import '../domain/recurrence_expander.dart';
import '../infrastructure/builder_calendar_client.dart';
import '../infrastructure/calendar_repository.dart';
import 'calendar_providers.dart';
import 'calendar_reminder_controller.dart';
import 'calendar_sync_service.dart';

export 'calendar_providers.dart'
    show builderCalendarClientProvider, calendarRepositoryProvider;

final calendarControllerProvider =
    NotifierProvider.family<CalendarController, CalendarState, String>(
      (ownerId) => CalendarController(ownerId),
    );

/// What the user must be told after a write; the UI maps it to RU/KK text.
enum CalendarWrite {
  saved,

  /// The outcome is unknown; the create is stored and will be replayed.
  queued,

  /// 412: the event changed on the server; nothing was overwritten.
  conflict,
  rejected,
  authRequired,
  offline,
}

enum CalendarProblem { none, auth, network }

class CalendarState {
  const CalendarState({
    required this.month,
    this.occurrences = const [],
    this.selectedDay,
    this.loading = true,
    this.problem = CalendarProblem.none,
    this.syncedAt,
    this.pending = const [],
    this.rejectedTitles = const [],
    this.recurringIds = const {},
  });

  /// First day of the displayed month.
  final DateTime month;
  final List<CalendarOccurrence> occurrences;
  final String? selectedDay;
  final bool loading;

  /// Set when the last refresh failed; [occurrences] then come from the cache.
  final CalendarProblem problem;
  final DateTime? syncedAt;
  final List<PendingCalendarCreate> pending;
  final List<String> rejectedTitles;

  /// Cached events that repeat; they offer per-occurrence actions.
  final Set<String> recurringIds;

  CalendarState copyWith({
    DateTime? month,
    List<CalendarOccurrence>? occurrences,
    String? selectedDay,
    bool clearSelectedDay = false,
    bool? loading,
    CalendarProblem? problem,
    DateTime? syncedAt,
    List<PendingCalendarCreate>? pending,
    List<String>? rejectedTitles,
    Set<String>? recurringIds,
  }) => CalendarState(
    month: month ?? this.month,
    occurrences: occurrences ?? this.occurrences,
    selectedDay: clearSelectedDay ? null : selectedDay ?? this.selectedDay,
    loading: loading ?? this.loading,
    problem: problem ?? this.problem,
    syncedAt: syncedAt ?? this.syncedAt,
    pending: pending ?? this.pending,
    rejectedTitles: rejectedTitles ?? this.rejectedTitles,
    recurringIds: recurringIds ?? this.recurringIds,
  );
}

class CalendarController extends Notifier<CalendarState> {
  CalendarController(this.ownerId);
  final String ownerId;
  int _generation = 0;

  BuilderCalendarClient? get _client => ref.read(builderCalendarClientProvider);
  CalendarRepository get _repo => ref.read(calendarRepositoryProvider);

  @override
  CalendarState build() {
    final now = DateTime.now();
    Future.microtask(refresh);
    return CalendarState(month: DateTime(now.year, now.month));
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  (String, String) _range(DateTime month) =>
      (_date(month), _date(DateTime(month.year, month.month + 1, 0)));

  Future<CalendarState> _fromCache(CalendarState base) async {
    final (from, to) = _range(base.month);
    final events = await _repo.events(ownerId);
    final overrides = await _repo.overrides(ownerId);
    return base.copyWith(
      occurrences: RecurrenceExpander.occurrences(events, from, to, overrides),
      syncedAt: await _repo.syncedAt(ownerId),
      pending: await _repo.pendingCreates(ownerId),
      recurringIds: {
        for (final e in events)
          if (e.recurrence != null) e.id,
      },
    );
  }

  Future<void> setMonth(DateTime month) async {
    state = state.copyWith(
      month: DateTime(month.year, month.month),
      clearSelectedDay: true,
    );
    await refresh();
  }

  void selectDay(String? day) => state = day == null
      ? state.copyWith(clearSelectedDay: true)
      : state.copyWith(selectedDay: day);

  /// Shows the cache at once, then syncs and refreshes the visible month.
  Future<void> refresh() async {
    final generation = ++_generation;
    final month = state.month;
    state = (await _fromCache(state)).copyWith(loading: true);
    if (generation != _generation) return;

    var problem = CalendarProblem.none;
    var rejected = const <String>[];
    final client = _client;
    if (client == null) {
      problem = CalendarProblem.network;
    } else {
      try {
        final service = CalendarSyncService(client: client, repository: _repo);
        final result = await service.sync(ownerId);
        rejected = [for (final p in result.rejected) '${p.input['title']}'];
        final (from, to) = _range(month);
        await service.refreshRange(ownerId, from, to);
      } on CraftAiAuthException {
        problem = CalendarProblem.auth;
      } catch (_) {
        problem = CalendarProblem.network;
      }
    }
    if (generation != _generation) return;
    state = (await _fromCache(
      state.copyWith(month: month),
    )).copyWith(loading: false, problem: problem, rejectedTitles: rejected);
    // Events or their reminders may have changed; keep the device's schedule in step.
    unawaited(
      ref
          .read(calendarReminderProvider(ownerId).notifier)
          .load(refreshWindow: problem == CalendarProblem.none),
    );
  }

  /// Stored event, fresh from the server when reachable.
  Future<CalendarEvent?> loadEvent(String id) async {
    try {
      final client = _client;
      if (client != null) return await client.event(id);
    } catch (_) {}
    for (final event in await _repo.events(ownerId)) {
      if (event.id == id) return event;
    }
    return null;
  }

  Future<CalendarWrite> create(
    Map<String, dynamic> input, {
    String? idempotencyKey,
  }) async {
    final client = _client;
    if (client == null) {
      // Keep the draft; it is sent once the API is reachable.
      await _repo.addPendingCreate(
        ownerId,
        PendingCalendarCreate(
          key: idempotencyKey ?? CraftAiClient.generateRequestId(),
          input: input,
          createdAtUtc: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      await refresh();
      return CalendarWrite.queued;
    }
    final outcome = await CalendarSyncService(
      client: client,
      repository: _repo,
    ).create(ownerId, input, idempotencyKey: idempotencyKey);
    await refresh();
    return switch (outcome) {
      CalendarCreateOutcome.saved => CalendarWrite.saved,
      CalendarCreateOutcome.queued => CalendarWrite.queued,
      CalendarCreateOutcome.rejected => CalendarWrite.rejected,
      CalendarCreateOutcome.authRequired => CalendarWrite.authRequired,
    };
  }

  Future<CalendarWrite> _write(Future<void> Function(BuilderCalendarClient) op) async {
    final client = _client;
    if (client == null) return CalendarWrite.offline;
    try {
      await op(client);
    } on CraftAiAuthException {
      return CalendarWrite.authRequired;
    } on CraftAiException catch (error) {
      if (error.statusCode == 412) {
        await refresh();
        return CalendarWrite.conflict;
      }
      if (error is CraftAiNetworkException || (error.statusCode ?? 500) >= 500) {
        return CalendarWrite.offline;
      }
      return CalendarWrite.rejected;
    } catch (_) {
      return CalendarWrite.offline;
    }
    await refresh();
    return CalendarWrite.saved;
  }

  Future<CalendarWrite> replace(CalendarEvent event, Map<String, dynamic> input) =>
      _write((c) => c.replace(event.id, event.version, input));

  Future<CalendarWrite> deleteSeries(String id) =>
      _write((c) => c.delete(id));

  Future<CalendarWrite> deleteFollowing(String id, String fromDate) =>
      _write((c) => c.delete(id, followingFrom: fromDate));

  Future<CalendarWrite> cancelOccurrence(String id, String date) =>
      _write((c) => c.overrideOccurrence(id, date, {'canceled': true}));

  Future<CalendarWrite> overrideOccurrence(
    String id,
    String date,
    Map<String, dynamic> input,
  ) => _write((c) => c.overrideOccurrence(id, date, input));

  Future<void> discardPending(String key) async {
    await _repo.removePendingCreate(ownerId, key);
    await refresh();
  }
}
