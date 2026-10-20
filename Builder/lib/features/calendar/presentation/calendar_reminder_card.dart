import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/calendar_reminder_controller.dart';
import '../application/calendar_reminder_service.dart';

/// Switch for local phone notifications about calendar reminders, with an
/// honest statement of what is scheduled and what is not promised.
class CalendarReminderCard extends ConsumerWidget {
  const CalendarReminderCard({super.key, required this.ownerId, required this.kk});
  final String ownerId;
  final bool kk;

  String _t(String ru, String kz) => kk ? kz : ru;

  static String _two(int value) => value.toString().padLeft(2, '0');

  String _when(DateTime utc) {
    final local = utc.toLocal();
    return '${_two(local.day)}.${_two(local.month)} ${_two(local.hour)}:${_two(local.minute)}';
  }

  String _status(ReminderUiState state) {
    if (state.refused) {
      return _t(
        'Разрешение на уведомления не выдано, напоминания остались выключенными. Его можно выдать в настройках телефона.',
        'Хабарландыруға рұқсат берілмеді, еске салулар өшірулі қалды. Рұқсатты телефон баптауларынан беруге болады.',
      );
    }
    switch (state.status) {
      case ReminderStatus.off:
        return _t(
          'Выключены. Телефон не будет напоминать о событиях.',
          'Өшірулі. Телефон оқиғалар туралы еске салмайды.',
        );
      case ReminderStatus.scheduled:
        final base = state.scheduled == 0
            ? _t(
                'В ближайшие 14 дней нет событий с напоминаниями.',
                'Алдағы 14 күнде еске салуы бар оқиға жоқ.',
              )
            : _t(
                'Запланировано: ${state.scheduled}. Ближайшее: ${_when(state.nextFireAtUtc!)}.',
                'Жоспарланды: ${state.scheduled}. Ең жақыны: ${_when(state.nextFireAtUtc!)}.',
              );
        return state.offline
            ? '$base ${_t('Сервер недоступен, использована копия на устройстве.', 'Сервер қолжетімсіз, құрылғыдағы көшірме қолданылды.')}'
            : base;
      case ReminderStatus.permissionDenied:
        return _t(
          'Уведомления для приложения запрещены, поэтому напоминания не придут. Разрешите их в настройках телефона.',
          'Қолданба үшін хабарландыру тыйым салынған, сондықтан еске салулар келмейді. Телефон баптауларынан рұқсат беріңіз.',
        );
      case ReminderStatus.unsupported:
        return _t(
          'На этом устройстве системные уведомления недоступны.',
          'Бұл құрылғыда жүйелік хабарландырулар қолжетімсіз.',
        );
      case ReminderStatus.failed:
        return _t(
          'Не удалось передать напоминания телефону. Откройте календарь позже.',
          'Еске салуларды телефонға тапсыру мүмкін болмады. Күнтізбені кейінірек ашыңыз.',
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarReminderProvider(ownerId));
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const Key('calendar.reminders.switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(_t('Напоминания на телефоне', 'Телефондағы еске салулар')),
              subtitle: Text(_status(state), key: const Key('calendar.reminders.status')),
              value: state.enabled,
              onChanged: state.loading
                  ? null
                  : (value) => ref
                        .read(calendarReminderProvider(ownerId).notifier)
                        .setEnabled(value),
            ),
            Text(
              _t(
                'Уведомление лишь сообщает о событии: оно не запускает ассистента и не готовит Daily Brief. Android может задержать его на несколько минут. Расписание строится на 14 дней вперёд при каждом открытии приложения.',
                'Хабарландыру тек оқиға туралы хабарлайды: ол ассистентті іске қоспайды және Daily Brief дайындамайды. Android оны бірнеше минутқа кешіктіруі мүмкін. Кесте қолданба ашылған сайын 14 күнге алдын ала құрылады.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
