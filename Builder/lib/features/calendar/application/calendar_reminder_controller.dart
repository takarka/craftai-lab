import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../session/session_repository.dart';
import '../infrastructure/reminder_scheduler.dart';
import 'calendar_providers.dart';
import 'calendar_reminder_service.dart';

/// The language chosen in the app, which texts of background notifications follow.
bool localeIsKazakh(Ref ref) => ref.read(appLocaleProvider)?.languageCode == 'kk';

class ReminderUiState {
  const ReminderUiState({
    this.loading = true,
    this.enabled = false,
    this.status = ReminderStatus.off,
    this.scheduled = 0,
    this.nextFireAtUtc,
    this.offline = false,

    /// The user asked to switch on, but the system does not allow notifications.
    this.refused = false,
  });

  final bool loading;
  final bool enabled;
  final ReminderStatus status;
  final int scheduled;
  final DateTime? nextFireAtUtc;
  final bool offline;
  final bool refused;
}

final calendarReminderProvider = NotifierProvider.autoDispose
    .family<CalendarReminderController, ReminderUiState, String>(
      (ownerId) => CalendarReminderController(ownerId),
    );

class CalendarReminderController extends Notifier<ReminderUiState> {
  CalendarReminderController(this.ownerId);
  final String ownerId;
  bool _disposed = false;

  CalendarReminderService get _service => ref.read(calendarReminderServiceProvider);

  @override
  ReminderUiState build() {
    ref.onDispose(() => _disposed = true);
    Future.microtask(load);
    return const ReminderUiState();
  }

  void _apply(ReminderUiState next) {
    if (!_disposed) state = next;
  }

  ReminderUiState _from(ReminderSyncResult result, {bool refused = false}) =>
      ReminderUiState(
        loading: false,
        enabled: result.status != ReminderStatus.off,
        status: result.status,
        scheduled: result.scheduled,
        nextFireAtUtc: result.nextFireAtUtc,
        offline: result.offline,
        refused: refused,
      );

  /// Re-plans from what the device knows; [refreshWindow] also asks the
  /// server which occurrences in the next weeks were cancelled or moved.
  Future<void> load({bool refreshWindow = false}) async {
    final result = await _service.sync(
      ownerId,
      kk: localeIsKazakh(ref),
      pullChanges: false,
      refreshWindow: refreshWindow,
    );
    _apply(_from(result));
  }

  Future<void> setEnabled(bool value) async {
    _apply(const ReminderUiState(loading: true));
    if (!value) {
      await _service.disable(ownerId);
      _apply(const ReminderUiState(loading: false));
      return;
    }
    final permission = await _service.enable(ownerId, kk: localeIsKazakh(ref));
    if (permission != ReminderPermission.granted) {
      _apply(
        ReminderUiState(
          loading: false,
          status: permission == ReminderPermission.unsupported
              ? ReminderStatus.unsupported
              : ReminderStatus.permissionDenied,
          refused: true,
        ),
      );
      return;
    }
    await load(refreshWindow: true);
  }
}

/// Re-plans reminders in the background: on sign-in, on every return to the
/// app, and removes them from the device when the account signs out.
final calendarReminderAutoSyncProvider = Provider<void>((ref) {
  final ownerId = ref.watch(
    sessionProvider.select((state) {
      final session = state.asData?.value;
      return session is AuthenticatedSession ? session.ownerId : null;
    }),
  );
  // While the session is still loading nothing is cancelled.
  final signedOut = ref.watch(
    sessionProvider.select((state) => state.asData?.value is SignedOut),
  );
  final service = ref.watch(calendarReminderServiceProvider);

  Future<void> run() async {
    if (ownerId == null) return;
    try {
      await service.sync(ownerId, kk: localeIsKazakh(ref));
    } catch (_) {
      // Reminders are best effort; the calendar screen reports their state.
    }
  }

  if (ownerId != null) {
    unawaited(run());
  } else if (signedOut) {
    unawaited(service.clearDevice());
  }
  final lifecycle = AppLifecycleListener(onResume: () => unawaited(run()));
  ref.onDispose(lifecycle.dispose);
});
