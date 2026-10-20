import 'package:builder/features/calendar/domain/reminder_planner.dart';
import 'package:builder/features/calendar/infrastructure/reminder_scheduler.dart';

class FakeScheduler implements ReminderScheduler {
  ReminderPermission current = ReminderPermission.granted;
  ReminderPermission onRequest = ReminderPermission.granted;
  bool failReplace = false;
  int requests = 0;
  int cancels = 0;
  final replaced = <List<PlannedReminder>>[];

  /// What the "device" holds after the last call, keyed by notification id.
  final held = <int, PlannedReminder>{};

  @override
  Future<ReminderPermission> permission() async => current;

  @override
  Future<ReminderPermission> requestPermission() async {
    requests++;
    current = onRequest;
    return current;
  }

  @override
  Future<void> replace(List<PlannedReminder> planned) async {
    if (failReplace) throw StateError('system refused');
    replaced.add(planned);
    held
      ..clear()
      ..addEntries(planned.map((r) => MapEntry(r.notificationId, r)));
  }

  @override
  Future<void> cancelAll() async {
    cancels++;
    held.clear();
  }
}
