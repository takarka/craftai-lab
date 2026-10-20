import 'dart:async';

import '../domain/reminder_planner.dart';
import '../infrastructure/builder_calendar_client.dart';
import '../infrastructure/calendar_repository.dart';
import '../infrastructure/reminder_scheduler.dart';
import 'calendar_sync_service.dart';

enum ReminderStatus {
  /// The owner has not switched calendar reminders on.
  off,

  /// Reminders are planned and handed to the system.
  scheduled,

  /// Switched on, but the system does not allow notifications right now.
  permissionDenied,
  unsupported,

  /// The system refused to take the schedule; nothing is promised.
  failed,
}

class ReminderSyncResult {
  const ReminderSyncResult({
    required this.status,
    this.scheduled = 0,
    this.nextFireAtUtc,
    this.offline = false,
  });

  final ReminderStatus status;
  final int scheduled;
  final DateTime? nextFireAtUtc;

  /// The server was tried and could not be reached, so the plan uses the offline cache.
  final bool offline;
}

/// Keeps the device's local notifications in step with the calendar: plans the
/// next 14 days from the cache, refreshing it first when the server answers.
class CalendarReminderService {
  CalendarReminderService({
    required this.repository,
    required this.scheduler,
    this.client,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final CalendarRepository repository;
  final ReminderScheduler scheduler;
  final BuilderCalendarClient? client;
  final DateTime Function() _now;

  // Cancelling and scheduling must not interleave between two syncs.
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() job) {
    final result = _tail.then((_) => job());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<bool> isEnabled(String ownerId) => repository.remindersEnabled(ownerId);

  Future<ReminderPermission> permission() => scheduler.permission();

  Future<void> _cancelQuietly() async {
    try {
      await scheduler.cancelAll();
    } catch (_) {
      // Nothing was scheduled that could still be cancelled here.
    }
  }

  /// Switches reminders on only when the system allows notifications; a
  /// refusal leaves them off so the screen never claims a delivery it cannot make.
  Future<ReminderPermission> enable(String ownerId, {bool kk = false}) async {
    var permission = await scheduler.permission();
    if (permission == ReminderPermission.denied) {
      permission = await scheduler.requestPermission();
    }
    if (permission != ReminderPermission.granted) return permission;
    await repository.setRemindersEnabled(ownerId, true);
    await sync(ownerId, kk: kk);
    return permission;
  }

  Future<void> disable(String ownerId) async {
    await repository.setRemindersEnabled(ownerId, false);
    await _serial(_cancelQuietly);
  }

  /// Removes every scheduled reminder from the device (sign-out, account deletion).
  Future<void> clearDevice() => _serial(_cancelQuietly);

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// Rebuilds the plan. [pullChanges] first downloads calendar changes and
  /// [refreshWindow] learns which occurrences in the reminder window were
  /// cancelled or moved; with both off the plan comes from the cache alone.
  Future<ReminderSyncResult> sync(
    String ownerId, {
    bool kk = false,
    bool pullChanges = true,
    bool refreshWindow = true,
  }) => _serial(() async {
    if (!await repository.remindersEnabled(ownerId)) {
      await _cancelQuietly();
      return const ReminderSyncResult(status: ReminderStatus.off);
    }
    final permission = await scheduler.permission();
    if (permission != ReminderPermission.granted) {
      await _cancelQuietly();
      return ReminderSyncResult(
        status: permission == ReminderPermission.unsupported
            ? ReminderStatus.unsupported
            : ReminderStatus.permissionDenied,
      );
    }

    var offline = false;
    final api = client;
    if (api != null && (pullChanges || refreshWindow)) {
      try {
        final service = CalendarSyncService(client: api, repository: repository);
        if (pullChanges) await service.sync(ownerId);
        final today = _now();
        if (refreshWindow) {
          await service.refreshRange(
            ownerId,
            _date(today.subtract(const Duration(days: 1))),
            _date(today.add(ReminderPlanner.horizon + const Duration(days: 8))),
          );
        }
      } catch (_) {
        offline = true;
        // Offline or signed out: the cache is still the best known calendar.
      }
    }

    try {
      final planned = ReminderPlanner.plan(
        events: await repository.events(ownerId),
        overrides: await repository.overrides(ownerId),
        now: _now(),
        kk: kk,
      );
      await scheduler.replace(planned);
      return ReminderSyncResult(
        status: ReminderStatus.scheduled,
        scheduled: planned.length,
        nextFireAtUtc: planned.isEmpty ? null : planned.first.fireAtUtc,
        offline: offline,
      );
    } catch (_) {
      return ReminderSyncResult(status: ReminderStatus.failed, offline: offline);
    }
  });
}
