import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../session/session_repository.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import '../infrastructure/builder_schedules_client.dart';

class ScheduleEditor extends ConsumerStatefulWidget {
  const ScheduleEditor({
    super.key,
    required this.ownerId,
    required this.template,
    this.schedule,
  });
  final String ownerId;
  final String template;
  final Json? schedule;
  @override
  ConsumerState<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends ConsumerState<ScheduleEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _zone,
      _time,
      _subject,
      _grade,
      _topics,
      _count;
  final _context = TextEditingController();
  late Set<String> _days;
  late String _language;
  bool _consent = false, _includeNotes = false, _enabled = true;
  bool get brief => widget.template == 'daily-brief';
  bool get kk => Localizations.localeOf(context).languageCode == 'kk';
  String t(String ru, String kz) => kk ? kz : ru;
  static const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  @override
  void initState() {
    super.initState();
    tzdata.initializeTimeZones();
    final s = widget.schedule;
    final timing = s?['timing'] as Map? ?? {};
    final p = s?['parameters'] as Map? ?? {};
    _zone = TextEditingController(
      text: s?['timeZone'] as String? ?? 'Asia/Almaty',
    );
    _time = TextEditingController(text: timing['time'] as String? ?? '07:30');
    _subject = TextEditingController(text: p['subject'] as String? ?? '');
    _grade = TextEditingController(text: '${p['grade'] ?? 5}');
    _topics = TextEditingController(
      text: (p['topics'] as List? ?? []).join('\n'),
    );
    _count = TextEditingController(text: '${p['ideasCount'] ?? 5}');
    _days = brief
        ? Set<String>.from(timing['weekdays'] as List? ?? days.take(5))
        : {timing['weekday'] as String? ?? 'mon'};
    _language = p['language'] as String? ?? 'ru';
    _includeNotes = p['includeNotes'] == true;
    _enabled = s?['enabled'] as bool? ?? true;
    _context.text = s?['extraContext'] as String? ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _zone,
      _time,
      _subject,
      _grade,
      _topics,
      _count,
      _context,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(
    TextEditingController c,
    String label, {
    String? Function(String)? validate,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label),
      maxLines: lines,
      validator: (value) => validate?.call(value?.trim() ?? ''),
    ),
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (_, next) {
      final session = next.value;
      if (session is! AuthenticatedSession ||
          session.ownerId != widget.ownerId) {
        for (final c in [
          _zone,
          _time,
          _subject,
          _grade,
          _topics,
          _count,
          _context,
        ]) {
          c.clear();
        }
        _consent = false;
      }
    });
    final session = ref.watch(sessionProvider).value;
    if (session is! AuthenticatedSession || session.ownerId != widget.ownerId) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(t('Войдите в аккаунт', 'Аккаунтқа кіріңіз'))),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          brief ? 'Daily Brief' : t('Генератор идей', 'Идеялар генераторы'),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              brief
                  ? t(
                      'Источник — события выбранного дня в календаре Builder.',
                      'Дереккөз — Builder күнтізбесіндегі таңдалған күн оқиғалары.',
                    )
                  : t(
                      'Источники — предмет, класс, темы и явно введённый фрагмент ниже.',
                      'Дереккөздер — пән, сынып, тақырыптар және төмендегі енгізілген үзінді.',
                    ),
            ),
            field(
              _zone,
              t('Часовой пояс IANA', 'IANA уақыт белдеуі'),
              validate: (v) {
                try {
                  tz.getLocation(v);
                  return null;
                } catch (_) {
                  return t(
                    'Неизвестный часовой пояс',
                    'Белгісіз уақыт белдеуі',
                  );
                }
              },
            ),
            Text(
              t(
                'Время привязано к этому поясу и не меняется при поездке. Для смены пояса измените расписание.',
                'Уақыт осы белдеуге байланысты, сапарда өзгермейді. Белдеуді ауыстыру үшін кестені өзгертіңіз.',
              ),
            ),
            field(
              _time,
              t('Время HH:mm', 'Уақыт HH:mm'),
              validate: (v) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v)
                  ? null
                  : t('Укажите время HH:mm', 'HH:mm уақытын енгізіңіз'),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (var i = 0; i < days.length; i++)
                  FilterChip(
                    label: Text(
                      (kk
                          ? ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сб', 'Жс']
                          : ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])[i],
                    ),
                    selected: _days.contains(days[i]),
                    onSelected: (value) => setState(() {
                      if (!brief) {
                        _days = {days[i]};
                      } else if (value) {
                        _days.add(days[i]);
                      } else {
                        _days.remove(days[i]);
                      }
                    }),
                  ),
              ],
            ),
            FormField<bool>(
              validator: (_) =>
                  _days.isEmpty ? t('Выберите день', 'Күнді таңдаңыз') : null,
              builder: (f) => f.hasError
                  ? Text(
                      f.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: InputDecoration(
                labelText: t('Язык результата', 'Нәтиже тілі'),
              ),
              items: const [
                DropdownMenuItem(value: 'ru', child: Text('Русский')),
                DropdownMenuItem(value: 'kk', child: Text('Қазақша')),
              ],
              onChanged: (v) => _language = v!,
            ),
            if (brief)
              SwitchListTile(
                title: Text(
                  t('Включать заметки событий', 'Оқиға жазбаларын қосу'),
                ),
                value: _includeNotes,
                onChanged: (v) => setState(() => _includeNotes = v),
              ),
            if (!brief) ...[
              field(
                _subject,
                t('Предмет', 'Пән'),
                validate: (v) => v.isEmpty || v.length > 100
                    ? t(
                        'Введите предмет (до 100 символов)',
                        'Пәнді енгізіңіз (100 таңбаға дейін)',
                      )
                    : null,
              ),
              field(
                _grade,
                t('Класс (1–11)', 'Сынып (1–11)'),
                validate: (v) =>
                    (int.tryParse(v) ?? 0) < 1 || (int.tryParse(v) ?? 99) > 11
                    ? t('Укажите класс 1–11', '1–11 сыныпты енгізіңіз')
                    : null,
              ),
              field(
                _topics,
                t(
                  'Темы: по одной в строке, до 10',
                  'Тақырыптар: әр жолға біреу, 10-ға дейін',
                ),
                lines: 3,
                validate: (v) =>
                    v.split('\n').where((v) => v.trim().isNotEmpty).length >
                            10 ||
                        v.split('\n').any((v) => v.trim().length > 100)
                    ? t(
                        'До 10 тем, до 100 символов каждая',
                        '10 тақырыпқа дейін, әрқайсысы 100 таңбаға дейін',
                      )
                    : null,
              ),
              field(
                _count,
                t('Количество идей (3–10)', 'Идея саны (3–10)'),
                validate: (v) =>
                    (int.tryParse(v) ?? 0) < 3 || (int.tryParse(v) ?? 99) > 10
                    ? t('Укажите 3–10', '3–10 енгізіңіз')
                    : null,
              ),
            ],
            field(
              _context,
              t(
                'Дополнительный фрагмент (необязательно)',
                'Қосымша үзінді (міндетті емес)',
              ),
              lines: 4,
              validate: (v) => utf8.encode(v).length > 20480 || v.length > 20000
                  ? t('Не больше 20 КБ', '20 КБ-тан аспауы тиіс')
                  : null,
            ),
            Text(
              t(
                'Память и знания автоматически не отправляются. Сохранённый фрагмент показан выше. Очистите поле, чтобы удалить его из расписания.',
                'Жад пен білім автоматты түрде жіберілмейді. Сақталған үзінді жоғарыда көрсетілген. Оны кестеден жою үшін өрісті тазалаңыз.',
              ),
            ),
            if (widget.schedule != null &&
                !widget.schedule!.containsKey('extraContext'))
              Text(
                t(
                  'Сервер не вернул сохранённый фрагмент. Сохранение заблокировано до обновления сервера, чтобы не потерять данные.',
                  'Сервер сақталған үзіндіні қайтармады. Деректерді жоғалтпау үшін сервер жаңартылғанша сақтау бұғатталған.',
                ),
              ),
            SwitchListTile(
              title: Text(t('Расписание включено', 'Кесте қосылған')),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            CheckboxListTile(
              value: _consent,
              onChanged: (v) => setState(() => _consent = v == true),
              title: Text(
                t(
                  'Согласен: расписание и результаты хранятся на сервере CraftAI. Для Daily Brief события дня, выбранные заметки и введённый фрагмент отправляются модели через OpenRouter; для идей — параметры и фрагмент. Результаты хранятся до 30 суток. Не указывайте персональные данные учеников.',
                  'Келісемін: кесте мен нәтижелер CraftAI серверінде сақталады. Daily Brief үшін күн оқиғалары, таңдалған жазбалар мен енгізілген үзінді OpenRouter арқылы модельге жіберіледі; идеялар үшін — параметрлер мен үзінді. Нәтижелер 30 күнге дейін сақталады. Оқушылардың жеке деректерін енгізбеңіз.',
                ),
              ),
            ),
            FilledButton(
              onPressed:
                  !_consent ||
                      (widget.schedule != null &&
                          !widget.schedule!.containsKey('extraContext'))
                  ? null
                  : () {
                      if (!_form.currentState!.validate()) return;
                      Navigator.pop(context, <String, dynamic>{
                        'enabled': _enabled,
                        'timeZone': _zone.text.trim(),
                        'timing': {
                          'time': _time.text.trim(),
                          if (brief)
                            'weekdays': days.where(_days.contains).toList()
                          else
                            'weekday': _days.single,
                        },
                        'parameters': {
                          'language': _language,
                          if (brief) 'includeNotes': _includeNotes,
                          if (!brief) ...{
                            'subject': _subject.text.trim(),
                            'grade': int.parse(_grade.text.trim()),
                            'topics': _topics.text
                                .split('\n')
                                .map((s) => s.trim())
                                .where((s) => s.isNotEmpty)
                                .toList(),
                            'ideasCount': int.parse(_count.text.trim()),
                          },
                        },
                        'extraContext': _context.text.trim().isEmpty
                            ? null
                            : _context.text.trim(),
                        'consentRevision': 'builder-schedules-v1',
                      });
                    },
              child: Text(t('Сохранить', 'Сақтау')),
            ),
          ],
        ),
      ),
    );
  }
}
