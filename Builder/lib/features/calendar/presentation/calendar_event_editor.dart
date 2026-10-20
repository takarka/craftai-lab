import 'package:flutter/material.dart';

import '../domain/calendar_models.dart';

/// Chooses between editing a whole event and one occurrence of a series.
enum CalendarEditorMode { event, occurrence }

class CalendarEditorResult {
  const CalendarEditorResult(this.json);

  /// Event input (mode `event`) or occurrence override body (mode `occurrence`).
  final Map<String, dynamic> json;
}

DateTime? parseLocalValue(String? value) {
  if (value == null || value.length < 10) return null;
  return DateTime.tryParse(
    value.length >= 19 ? value.substring(0, 19) : '${value.substring(0, 10)}T00:00:00',
  );
}

String _two(int value) => value.toString().padLeft(2, '0');

String formatDay(DateTime v) => '${v.year.toString().padLeft(4, '0')}-${_two(v.month)}-${_two(v.day)}';

String formatLocalValue(DateTime v, {required bool allDay}) => allDay
    ? formatDay(v)
    : '${formatDay(v)}T${_two(v.hour)}:${_two(v.minute)}:${_two(v.second)}';

final _zonePattern = RegExp(r'^(UTC|[A-Za-z_]+(/[A-Za-z0-9_+\-]+)+)$');

class CalendarEventEditor extends StatefulWidget {
  const CalendarEventEditor({
    super.key,
    this.event,
    this.occurrence,
    this.mode = CalendarEditorMode.event,
    required this.kk,
    this.initialDay,
  });

  final CalendarEvent? event;

  /// The occurrence being edited in `occurrence` mode.
  final CalendarOccurrence? occurrence;
  final CalendarEditorMode mode;
  final bool kk;
  final DateTime? initialDay;

  @override
  State<CalendarEventEditor> createState() => _CalendarEventEditorState();
}

class _CalendarEventEditorState extends State<CalendarEventEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _zone, _notes, _subject, _count, _interval;
  late bool _allDay;
  late DateTime _start, _end;
  String _frequency = 'none';
  Set<int> _weekdays = {};
  String _endKind = 'never';
  DateTime? _until;
  int? _grade;
  List<int> _reminders = [];
  String? _error;

  bool get _occurrenceMode => widget.mode == CalendarEditorMode.occurrence;
  String t(String ru, String kk) => widget.kk ? kk : ru;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final occurrence = widget.occurrence;
    final day = widget.initialDay ?? DateTime.now();
    _allDay = occurrence?.allDay ?? event?.allDay ?? false;
    _start =
        parseLocalValue(occurrence?.start ?? event?.start) ??
        DateTime(day.year, day.month, day.day, 9);
    _end =
        parseLocalValue(occurrence?.end ?? event?.end) ??
        DateTime(day.year, day.month, day.day, 10);
    _title = TextEditingController(text: occurrence?.title ?? event?.title ?? '');
    _notes = TextEditingController(text: occurrence?.notes ?? event?.notes ?? '');
    _zone = TextEditingController(text: event?.timeZone ?? 'Asia/Almaty');
    _subject = TextEditingController(text: event?.subject ?? '');
    _grade = event?.grade;
    _reminders = List.of(event?.reminders ?? const []);
    final rule = event?.recurrence;
    _frequency = rule?.frequency ?? 'none';
    _weekdays = {...?rule?.byWeekday};
    if (_frequency == 'weekly' && _weekdays.isEmpty) _weekdays = {_start.weekday};
    _interval = TextEditingController(text: '${rule?.interval ?? 1}');
    _count = TextEditingController(text: '${rule?.count ?? 10}');
    if (rule?.count != null) {
      _endKind = 'count';
    } else if (rule?.until != null) {
      _endKind = 'until';
      _until = parseLocalValue(rule!.until);
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _zone, _notes, _subject, _count, _interval]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final merged = DateTime(picked.year, picked.month, picked.day, current.hour, current.minute);
      if (start) {
        final span = _end.difference(_start);
        _start = merged;
        _end = merged.add(span);
      } else {
        _end = merged;
      }
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    setState(() {
      final merged = DateTime(current.year, current.month, current.day, picked.hour, picked.minute);
      if (start) {
        final span = _end.difference(_start);
        _start = merged;
        _end = merged.add(span);
      } else {
        _end = merged;
      }
    });
  }

  Future<void> _pickUntil() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _until ?? _start,
      firstDate: DateTime(_start.year, _start.month, _start.day),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _until = picked);
  }

  Future<void> _addReminder() async {
    final controller = TextEditingController(text: '15');
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Напомнить за (минут)', 'Еске салу (минут бұрын)')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Отмена', 'Болдырмау')),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null && value >= 0 && value <= 10080) {
                Navigator.pop(context, value);
              }
            },
            child: Text(t('Добавить', 'Қосу')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (minutes != null && !_reminders.contains(minutes)) {
      setState(() => _reminders = [..._reminders, minutes]..sort());
    }
  }

  String? _validateTimes() {
    if (_allDay) {
      final s = DateTime(_start.year, _start.month, _start.day);
      final e = DateTime(_end.year, _end.month, _end.day);
      if (e.isBefore(s)) {
        return t('Конец должен быть не раньше начала.', 'Аяқталуы басталуынан ерте болмауы керек.');
      }
    } else if (!_end.isAfter(_start)) {
      return t('Конец должен быть после начала.', 'Аяқталуы басталуынан кейін болуы керек.');
    }
    return null;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final timeError = _validateTimes();
    if (timeError != null) {
      setState(() => _error = timeError);
      return;
    }
    final start = formatLocalValue(_start, allDay: _allDay);
    final end = formatLocalValue(_end, allDay: _allDay);
    if (_occurrenceMode) {
      Navigator.pop(
        context,
        CalendarEditorResult({
          'title': _title.text.trim(),
          'notes': _notes.text.trim(),
          'start': start,
          'end': end,
        }),
      );
      return;
    }

    CalendarRecurrence? recurrence;
    if (_frequency != 'none') {
      final interval = int.parse(_interval.text.trim());
      final sorted = _weekdays.toList()..sort();
      if (_frequency == 'weekly' && sorted.isEmpty) {
        setState(() => _error = t('Выберите дни недели.', 'Апта күндерін таңдаңыз.'));
        return;
      }
      if (_endKind == 'until' && _until == null) {
        setState(() => _error = t('Укажите дату окончания.', 'Аяқталу күнін көрсетіңіз.'));
        return;
      }
      recurrence = CalendarRecurrence(
        frequency: _frequency,
        interval: interval,
        byWeekday: _frequency == 'weekly' ? sorted : const [],
        until: _endKind == 'until' ? formatDay(_until!) : null,
        count: _endKind == 'count' ? int.parse(_count.text.trim()) : null,
        excludedDates: widget.event?.recurrence?.excludedDates ?? const [],
      );
    }
    final subject = _subject.text.trim();
    final input = CalendarEvent(
      id: '',
      version: 0,
      title: _title.text.trim(),
      notes: _notes.text.trim(),
      allDay: _allDay,
      start: start,
      end: end,
      timeZone: _allDay ? null : _zone.text.trim(),
      recurrence: recurrence,
      reminders: _reminders,
      subject: subject.isEmpty ? null : subject,
      grade: _grade,
    ).toInputJson();
    Navigator.pop(context, CalendarEditorResult(input));
  }

  String _dateLabel(DateTime v) => formatDay(v);
  String _timeLabel(DateTime v) => '${_two(v.hour)}:${_two(v.minute)}';

  Widget _dateTimeRow(String label, DateTime value, {required bool start}) => Row(
    children: [
      Expanded(child: Text(label)),
      TextButton(
        onPressed: () => _pickDate(start: start),
        child: Text(_dateLabel(value)),
      ),
      if (!_allDay)
        TextButton(
          onPressed: () => _pickTime(start: start),
          child: Text(_timeLabel(value)),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final weekdayLabels = widget.kk
        ? ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сб', 'Жс']
        : ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return AlertDialog(
      title: Text(
        _occurrenceMode
            ? t('Это вхождение', 'Осы қайталану')
            : t('Событие', 'Оқиға'),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _title,
                  maxLength: 200,
                  decoration: InputDecoration(labelText: t('Название', 'Атауы')),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? t('Введите название', 'Атауын енгізіңіз')
                      : null,
                ),
                if (!_occurrenceMode)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('Весь день', 'Күні бойы')),
                    value: _allDay,
                    onChanged: (value) => setState(() {
                      _allDay = value;
                      if (!value && _end == _start) {
                        _end = _start.add(const Duration(hours: 1));
                      }
                    }),
                  ),
                _dateTimeRow(t('Начало', 'Басталуы'), _start, start: true),
                _dateTimeRow(t('Конец', 'Аяқталуы'), _end, start: false),
                if (!_allDay && !_occurrenceMode)
                  TextFormField(
                    controller: _zone,
                    decoration: InputDecoration(
                      labelText: t('Часовой пояс IANA', 'IANA уақыт белдеуі'),
                    ),
                    validator: (v) => v != null && _zonePattern.hasMatch(v.trim())
                        ? null
                        : t('Например, Asia/Almaty', 'Мысалы, Asia/Almaty'),
                  ),
                TextFormField(
                  controller: _notes,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: t('Заметки', 'Жазбалар')),
                ),
                if (!_occurrenceMode) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _frequency,
                    decoration: InputDecoration(labelText: t('Повторение', 'Қайталау')),
                    items: [
                      DropdownMenuItem(value: 'none', child: Text(t('Не повторять', 'Қайталамау'))),
                      DropdownMenuItem(value: 'daily', child: Text(t('Каждый день', 'Күн сайын'))),
                      DropdownMenuItem(value: 'weekly', child: Text(t('По дням недели', 'Апта күндері бойынша'))),
                    ],
                    onChanged: (value) => setState(() {
                      _frequency = value ?? 'none';
                      if (_frequency == 'weekly' && _weekdays.isEmpty) {
                        _weekdays = {_start.weekday};
                      }
                    }),
                  ),
                  if (_frequency != 'none') ...[
                    TextFormField(
                      controller: _interval,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _frequency == 'daily'
                            ? t('Каждые N дней (1–52)', 'Әр N күн (1–52)')
                            : t('Каждые N недель (1–52)', 'Әр N апта (1–52)'),
                      ),
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        return n != null && n >= 1 && n <= 52
                            ? null
                            : t('От 1 до 52', '1-ден 52-ге дейін');
                      },
                    ),
                    if (_frequency == 'weekly')
                      Wrap(
                        spacing: 6,
                        children: [
                          for (var day = 1; day <= 7; day++)
                            FilterChip(
                              label: Text(weekdayLabels[day - 1]),
                              selected: _weekdays.contains(day),
                              onSelected: (on) => setState(
                                () => on ? _weekdays.add(day) : _weekdays.remove(day),
                              ),
                            ),
                        ],
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: _endKind,
                      decoration: InputDecoration(labelText: t('Окончание', 'Аяқталуы')),
                      items: [
                        DropdownMenuItem(value: 'never', child: Text(t('Без окончания', 'Шексіз'))),
                        DropdownMenuItem(value: 'until', child: Text(t('До даты', 'Күнге дейін'))),
                        DropdownMenuItem(value: 'count', child: Text(t('Число повторений', 'Қайталау саны'))),
                      ],
                      onChanged: (value) => setState(() => _endKind = value ?? 'never'),
                    ),
                    if (_endKind == 'until')
                      TextButton(
                        onPressed: _pickUntil,
                        child: Text(_until == null ? t('Выбрать дату', 'Күнді таңдау') : _dateLabel(_until!)),
                      ),
                    if (_endKind == 'count')
                      TextFormField(
                        controller: _count,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: t('Всего вхождений (1–366)', 'Барлығы (1–366)')),
                        validator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          return n != null && n >= 1 && n <= 366
                              ? null
                              : t('От 1 до 366', '1-ден 366-ға дейін');
                        },
                      ),
                    if ((widget.event?.recurrence?.excludedDates ?? const []).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(t(
                          'Пропущенные даты серии сохранятся.',
                          'Топтаманың өткізілген күндері сақталады.',
                        )),
                      ),
                  ],
                  const SizedBox(height: 8),
                  Text(t('Напоминания (хранятся на сервере)', 'Еске салулар (серверде сақталады)')),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final minutes in _reminders)
                        InputChip(
                          label: Text(minutes == 0
                              ? t('В момент начала', 'Басталған кезде')
                              : t('За $minutes мин', '$minutes мин бұрын')),
                          onDeleted: () => setState(() => _reminders = _reminders.where((m) => m != minutes).toList()),
                        ),
                      if (_reminders.length < 3)
                        ActionChip(
                          label: Text(t('Добавить', 'Қосу')),
                          onPressed: _addReminder,
                        ),
                    ],
                  ),
                  TextFormField(
                    controller: _subject,
                    maxLength: 100,
                    decoration: InputDecoration(labelText: t('Предмет', 'Пән')),
                  ),
                  DropdownButtonFormField<int?>(
                    initialValue: _grade,
                    decoration: InputDecoration(labelText: t('Класс', 'Сынып')),
                    items: [
                      DropdownMenuItem(value: null, child: Text(t('Не указан', 'Көрсетілмеген'))),
                      for (var g = 1; g <= 11; g++) DropdownMenuItem(value: g, child: Text('$g')),
                    ],
                    onChanged: (value) => setState(() => _grade = value),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Отмена', 'Болдырмау')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(t('Сохранить на сервере', 'Серверде сақтау')),
        ),
      ],
    );
  }
}
