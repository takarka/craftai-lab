import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_providers.dart';
import '../../models/model_providers.dart';
import '../infrastructure/builder_calendar_client.dart';
import '../infrastructure/calendar_repository.dart';
import '../infrastructure/reminder_scheduler.dart';
import 'calendar_reminder_service.dart';

final builderCalendarClientProvider = Provider<BuilderCalendarClient?>((ref) {
  final api = ref.watch(craftAiClientProvider);
  return api == null ? null : BuilderCalendarClient(api);
});

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  final db = ref.watch(storageDatabaseProvider);
  if (db == null) return InMemoryCalendarRepository();
  return PersistentCalendarRepository(database: db);
});

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => SystemReminderScheduler(),
);

final calendarReminderServiceProvider = Provider<CalendarReminderService>(
  (ref) => CalendarReminderService(
    repository: ref.watch(calendarRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    client: ref.watch(builderCalendarClientProvider),
  ),
);
