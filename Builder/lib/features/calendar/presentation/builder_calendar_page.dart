import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/calendar_controller.dart';
import '../domain/calendar_models.dart';
import 'calendar_event_editor.dart';

export '../application/calendar_controller.dart' show builderCalendarClientProvider;

enum _Action { edit, editOccurrence, cancelOccurrence, deleteFollowing, deleteAll }

class BuilderCalendarPage extends ConsumerStatefulWidget {
  const BuilderCalendarPage({super.key, required this.ownerId});
  final String ownerId;
  @override
  ConsumerState<BuilderCalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<BuilderCalendarPage> {
  bool get _kk => Localizations.localeOf(context).languageCode == 'kk';
  String _text(String ru, String kk) => _kk ? kk : ru;

  CalendarController get _controller =>
      ref.read(calendarControllerProvider(widget.ownerId).notifier);

  String _writeMessage(CalendarWrite result) => switch (result) {
    CalendarWrite.saved => _text('Сохранено на сервере.', 'Серверде сақталды.'),
    CalendarWrite.queued => _text(
      'Нет ответа сервера. Событие сохранено на устройстве и будет отправлено повторно без дублей.',
      'Сервер жауап бермеді. Оқиға құрылғыда сақталды, қайталанбай қайта жіберіледі.',
    ),
    CalendarWrite.conflict => _text(
      'Событие изменилось. Календарь обновлён, повторите правку.',
      'Оқиға өзгерді. Күнтізбе жаңартылды, өңдеуді қайталаңыз.',
    ),
    CalendarWrite.rejected => _text(
      'Сервер не принял изменения. Проверьте данные.',
      'Сервер өзгерістерді қабылдамады. Деректерді тексеріңіз.',
    ),
    CalendarWrite.authRequired => _text(
      'Войдите в аккаунт заново.',
      'Аккаунтқа қайта кіріңіз.',
    ),
    CalendarWrite.offline => _text(
      'Нужно соединение с сервером. Изменения не сохранены.',
      'Сервермен байланыс қажет. Өзгерістер сақталмады.',
    ),
  };

  void _report(CalendarWrite result) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_writeMessage(result))),
    );
  }

  Future<void> _create(DateTime day) async {
    final result = await showDialog<CalendarEditorResult>(
      context: context,
      builder: (_) => CalendarEventEditor(kk: _kk, initialDay: day),
    );
    if (result == null || !mounted) return;
    _report(await _controller.create(result.json));
  }

  Future<void> _editEvent(String id) async {
    final event = await _controller.loadEvent(id);
    if (event == null || !mounted) return;
    final result = await showDialog<CalendarEditorResult>(
      context: context,
      builder: (_) => CalendarEventEditor(event: event, kk: _kk),
    );
    if (result == null || !mounted) return;
    _report(await _controller.replace(event, result.json));
  }

  Future<void> _editOccurrence(CalendarOccurrence item) async {
    final result = await showDialog<CalendarEditorResult>(
      context: context,
      builder: (_) => CalendarEventEditor(
        occurrence: item,
        mode: CalendarEditorMode.occurrence,
        kk: _kk,
      ),
    );
    if (result == null || !mounted) return;
    _report(
      await _controller.overrideOccurrence(
        item.eventId,
        item.occurrenceDate,
        result.json,
      ),
    );
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_text('Отмена', 'Болдырмау')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  Future<void> _perform(_Action action, CalendarOccurrence item) async {
    switch (action) {
      case _Action.edit:
        return _editEvent(item.eventId);
      case _Action.editOccurrence:
        return _editOccurrence(item);
      case _Action.cancelOccurrence:
        if (await _confirm(
          _text('Отменить это вхождение?', 'Осы қайталануды болдырмау керек пе?'),
          _text('Остальные вхождения серии не изменятся.', 'Топтаманың басқа қайталанулары өзгермейді.'),
          _text('Отменить', 'Болдырмау'),
        )) {
          _report(await _controller.cancelOccurrence(item.eventId, item.occurrenceDate));
        }
      case _Action.deleteFollowing:
        if (await _confirm(
          _text('Удалить это и следующие?', 'Осыны және келесілерін жою керек пе?'),
          _text('Вхождения до ${item.occurrenceDate} сохранятся.', '${item.occurrenceDate} дейінгі қайталанулар сақталады.'),
          _text('Удалить', 'Жою'),
        )) {
          _report(await _controller.deleteFollowing(item.eventId, item.occurrenceDate));
        }
      case _Action.deleteAll:
        final recurring = ref
            .read(calendarControllerProvider(widget.ownerId))
            .recurringIds
            .contains(item.eventId);
        if (await _confirm(
          _text('Удалить событие?', 'Оқиғаны жою керек пе?'),
          recurring
              ? _text('Повторяющееся событие будет удалено целиком.', 'Қайталанатын оқиға толығымен жойылады.')
              : _text('Событие будет удалено с сервера.', 'Оқиға серверден жойылады.'),
          _text('Удалить', 'Жою'),
        )) {
          _report(await _controller.deleteSeries(item.eventId));
        }
    }
  }

  String _problemText(CalendarProblem problem) => switch (problem) {
    CalendarProblem.auth => _text('Войдите в аккаунт заново.', 'Аккаунтқа қайта кіріңіз.'),
    CalendarProblem.network => _text(
      'Не удалось обновить календарь. Проверьте соединение и повторите.',
      'Күнтізбені жаңарту мүмкін болмады. Байланысты тексеріп, қайталаңыз.',
    ),
    CalendarProblem.none => '',
  };

  String _time(CalendarOccurrence item) => item.allDay
      ? _text('Весь день', 'Күні бойы')
      : '${item.start.substring(11, 16)}–${item.end.substring(11, 16)}'
            '${item.start.substring(0, 10) == item.end.substring(0, 10) ? '' : ' (${item.end.substring(0, 10)})'}';

  List<CalendarOccurrence> _forDay(CalendarState state, String day) => [
    for (final o in state.occurrences)
      if (o.startDate.compareTo(day) <= 0 && o.end.substring(0, 10).compareTo(day) >= 0) o,
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(calendarControllerProvider(widget.ownerId));
    final month = state.month;
    final now = DateTime.now();
    final today = formatDay(now);
    final monthPrefix = formatDay(month).substring(0, 8);
    final selected = state.selectedDay ??
        (today.startsWith(monthPrefix) ? today : '${monthPrefix}01');
    final selectedItems = _forDay(state, selected);
    final firstOffset = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final weekdayLabels = _kk
        ? ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сб', 'Жс']
        : ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_text('Календарь Builder', 'Builder күнтізбесі')),
        actions: [
          IconButton(
            onPressed: () => _controller.refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: _text('Обновить', 'Жаңарту'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _create(DateTime.tryParse(selected) ?? now),
        tooltip: _text('Создать событие', 'Оқиға жасау'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => _controller.refresh(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _text(
                  'События хранятся на сервере CraftAI и удаляются с аккаунтом. Копия для офлайна лежит на устройстве. Не указывайте персональные данные учеников.',
                  'Оқиғалар CraftAI серверінде сақталады және аккаунтпен бірге жойылады. Офлайн көшірмесі құрылғыда тұрады. Оқушылардың жеке деректерін жазбаңыз.',
                ),
              ),
            ),
            if (state.problem != CalendarProblem.none)
              _Banner(
                icon: Icons.cloud_off,
                text: '${_problemText(state.problem)}'
                    '${state.syncedAt == null ? '' : '\n${_text('Показаны данные от', 'Деректер күні:')} ${state.syncedAt!.toLocal().toString().substring(0, 16)}'}',
              ),
            if (state.pending.isNotEmpty)
              _Banner(
                icon: Icons.schedule_send,
                text: _text(
                  'Ожидают отправки: ${state.pending.map((p) => p.input['title']).join(', ')}',
                  'Жіберуді күтуде: ${state.pending.map((p) => p.input['title']).join(', ')}',
                ),
                action: TextButton(
                  onPressed: () => _controller.discardPending(state.pending.first.key),
                  child: Text(_text('Отменить', 'Болдырмау')),
                ),
              ),
            if (state.rejectedTitles.isNotEmpty)
              _Banner(
                icon: Icons.error_outline,
                text: _text(
                  'Сервер отклонил: ${state.rejectedTitles.join(', ')}',
                  'Сервер қабылдамады: ${state.rejectedTitles.join(', ')}',
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: _text('Предыдущий месяц', 'Алдыңғы ай'),
                  onPressed: () => _controller.setMonth(DateTime(month.year, month.month - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${month.month.toString().padLeft(2, '0')}.${month.year}'),
                IconButton(
                  tooltip: _text('Следующий месяц', 'Келесі ай'),
                  onPressed: () => _controller.setMonth(DateTime(month.year, month.month + 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (state.loading) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final label in weekdayLabels)
                        Expanded(child: Center(child: Text(label))),
                    ],
                  ),
                  for (var row = 0; row < ((firstOffset + daysInMonth + 6) ~/ 7); row++)
                    Row(
                      children: [
                        for (var col = 0; col < 7; col++)
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final day = row * 7 + col - firstOffset + 1;
                                if (day < 1 || day > daysInMonth) {
                                  return const SizedBox(height: 44);
                                }
                                final key = '$monthPrefix${day.toString().padLeft(2, '0')}';
                                final count = _forDay(state, key).length;
                                final isSelected = key == selected;
                                return Semantics(
                                  button: true,
                                  selected: isSelected,
                                  label: _text(
                                    '$day число, событий: $count',
                                    '$day күні, оқиғалар: $count',
                                  ),
                                  child: InkWell(
                                    onTap: () => _controller.selectDay(key),
                                    child: Container(
                                      height: 44,
                                      margin: const EdgeInsets.all(1),
                                      decoration: BoxDecoration(
                                        color: isSelected ? scheme.primaryContainer : null,
                                        border: key == today
                                            ? Border.all(color: scheme.primary)
                                            : null,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text('$day'),
                                          if (count > 0)
                                            Icon(Icons.circle, size: 6, color: scheme.primary),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(selected, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (!state.loading && selectedItems.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  state.occurrences.isEmpty
                      ? _text('В этом месяце нет событий.', 'Бұл айда оқиғалар жоқ.')
                      : _text('В этот день нет событий.', 'Бұл күні оқиғалар жоқ.'),
                ),
              ),
            for (final item in selectedItems)
              ListTile(
                key: ValueKey('${item.eventId}|${item.occurrenceDate}'),
                title: Text(item.title),
                subtitle: Text(
                  '${_time(item)}${item.timeZone == null ? '' : '\n${item.timeZone}'}',
                ),
                isThreeLine: item.timeZone != null,
                onTap: () => _editEvent(item.eventId),
                trailing: PopupMenuButton<_Action>(
                  tooltip: _text('Действия', 'Әрекеттер'),
                  onSelected: (action) => _perform(action, item),
                  itemBuilder: (context) {
                    final recurring = state.recurringIds.contains(item.eventId);
                    return [
                      PopupMenuItem(
                        value: _Action.edit,
                        child: Text(recurring ? _text('Изменить серию', 'Топтаманы өзгерту') : _text('Изменить', 'Өзгерту')),
                      ),
                      if (recurring) ...[
                        PopupMenuItem(value: _Action.editOccurrence, child: Text(_text('Изменить только это', 'Тек осыны өзгерту'))),
                        PopupMenuItem(value: _Action.cancelOccurrence, child: Text(_text('Отменить только это', 'Тек осыны болдырмау'))),
                        PopupMenuItem(value: _Action.deleteFollowing, child: Text(_text('Удалить это и следующие', 'Осыны және келесілерін жою'))),
                      ],
                      PopupMenuItem(
                        value: _Action.deleteAll,
                        child: Text(recurring ? _text('Удалить всю серию', 'Бүкіл топтаманы жою') : _text('Удалить', 'Жою')),
                      ),
                    ];
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
        ?action,
      ],
    ),
  );
}
