import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../tools/domain/tool_definition.dart';

/// Frequency options for educational reminders (F16-05).
enum ReminderFrequency {
  disabled(
    'Отключены',
    'Өшірулі',
    'Уведомления не отправляются',
    'Хабарландырулар жіберілмейді',
  ),
  daily(
    'Ежедневно',
    'Күн сайын',
    'Каждый вечер в 18:00',
    'Күн сайын сағат 18:00-де',
  ),
  weekdays(
    'По будням (Пн–Пт)',
    'Жұмыс күндері (Дс–Жм)',
    'С понедельника по пятницу в 17:30',
    'Дүйсенбіден жұмаға дейін сағат 17:30-да',
  ),
  weekly(
    'Раз в неделю',
    'Аптасына бір рет',
    'По субботам в 11:00',
    'Сенбі күндері сағат 11:00-де',
  );

  final String labelRu;
  final String labelKk;
  final String scheduleRu;
  final String scheduleKk;

  const ReminderFrequency(
    this.labelRu,
    this.labelKk,
    this.scheduleRu,
    this.scheduleKk,
  );

  String label(bool isKk) => isKk ? labelKk : labelRu;
  String schedule(bool isKk) => isKk ? scheduleKk : scheduleRu;
}

/// Representation of a scheduled local notification (F16-05).
class ScheduledReminder {
  final String id;
  final String title;
  final String body;
  final String scheduledTime;

  const ScheduledReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledTime,
  });
}

/// State of the reminder service (F16-05).
class ReminderState {
  final ReminderFrequency frequency;
  final OsPermissionStatus permissionStatus;
  final List<ScheduledReminder> scheduledReminders;

  const ReminderState({
    this.frequency = ReminderFrequency.disabled,
    this.permissionStatus = OsPermissionStatus.notRequested,
    this.scheduledReminders = const [],
  });

  bool get hasPermission => permissionStatus == OsPermissionStatus.granted;

  ReminderState copyWith({
    ReminderFrequency? frequency,
    OsPermissionStatus? permissionStatus,
    List<ScheduledReminder>? scheduledReminders,
  }) {
    return ReminderState(
      frequency: frequency ?? this.frequency,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      scheduledReminders: scheduledReminders ?? this.scheduledReminders,
    );
  }
}

/// Notifier managing course reminder frequency, OS notification permission and cancellation (F16-05).
class ReminderNotifier extends Notifier<ReminderState> {
  @override
  ReminderState build() {
    return const ReminderState();
  }

  /// Updates OS permission status.
  void setPermissionStatus(OsPermissionStatus status) {
    if (status != OsPermissionStatus.granted && state.frequency != ReminderFrequency.disabled) {
      cancelAll();
      state = state.copyWith(permissionStatus: status);
      return;
    }
    state = state.copyWith(permissionStatus: status);
    if (state.hasPermission && state.frequency != ReminderFrequency.disabled) {
      state = state.copyWith(scheduledReminders: _buildReminders(state.frequency));
    }
  }

  /// Sets reminder frequency. If disabled, cancels all notifications.
  /// If enabled and permission is granted, schedules reminder fixtures.
  void setFrequency(ReminderFrequency newFrequency) {
    if (newFrequency == ReminderFrequency.disabled) {
      cancelAll();
      return;
    }

    final reminders = state.hasPermission ? _buildReminders(newFrequency) : <ScheduledReminder>[];
    state = state.copyWith(
      frequency: newFrequency,
      scheduledReminders: reminders,
    );
  }

  /// Cancels all scheduled local notifications and resets frequency to disabled (F16-05).
  void cancelAll() {
    state = state.copyWith(
      frequency: ReminderFrequency.disabled,
      scheduledReminders: const [],
    );
  }

  static List<ScheduledReminder> _buildReminders(ReminderFrequency frequency) {
    switch (frequency) {
      case ReminderFrequency.disabled:
        return const [];
      case ReminderFrequency.daily:
        return const [
          ScheduledReminder(
            id: 'rem_daily_course',
            title: 'Курс CraftAI: Время для нового модуля',
            body: 'Уделите 10 минут практике с ассистентом, чтобы закрепить материал.',
            scheduledTime: '18:00 ежедневно',
          ),
        ];
      case ReminderFrequency.weekdays:
        return const [
          ScheduledReminder(
            id: 'rem_weekdays_prep',
            title: 'Подготовка к урокам',
            body: 'Составьте план урока и проверочные карточки вместе с ассистентом.',
            scheduledTime: '17:30 Пн–Пт',
          ),
        ];
      case ReminderFrequency.weekly:
        return const [
          ScheduledReminder(
            id: 'rem_weekly_review',
            title: 'Недельный дайджест курса',
            body: 'Повторите изученные термины и пополните базу документов ассистента.',
            scheduledTime: '11:00 Суббота',
          ),
        ];
    }
  }
}
