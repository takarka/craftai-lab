import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/model_providers.dart';
import '../../models/infrastructure/craft_ai_client.dart';
import '../infrastructure/builder_calendar_client.dart';

final builderCalendarClientProvider = Provider<BuilderCalendarClient?>((ref) {
  final api = ref.watch(craftAiClientProvider);
  return api == null ? null : BuilderCalendarClient(api);
});

class BuilderCalendarPage extends ConsumerStatefulWidget {
  const BuilderCalendarPage({super.key});
  @override
  ConsumerState<BuilderCalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<BuilderCalendarPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  int _generation = 0;
  bool get _kk => Localizations.localeOf(context).languageCode == 'kk';
  String _text(String ru, String kk) => _kk ? kk : ru;
  String _date(DateTime value) => value.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  String _failure(Object error) {
    if (error is CraftAiAuthException) {
      return _text('Войдите в аккаунт заново.', 'Аккаунтқа қайта кіріңіз.');
    }
    if (error is CraftAiException && error.statusCode == 412) {
      return _text(
        'Событие изменилось. Обновите календарь и повторите правку.',
        'Оқиға өзгерді. Күнтізбені жаңартып, қайта өңдеңіз.',
      );
    }
    return _text(
      'Не удалось загрузить или сохранить календарь. Проверьте соединение и повторите.',
      'Күнтізбені жүктеу немесе сақтау мүмкін болмады. Байланысты тексеріп, қайталаңыз.',
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
    });
    try {
      final client = ref.read(builderCalendarClientProvider);
      if (client == null) throw StateError('API unavailable');
      final result = await client.occurrences(
        _date(_month),
        _date(DateTime(_month.year, _month.month + 1, 0)),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = (result['items'] as List).cast<Map<String, dynamic>>();
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _failure(error);
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit([String? id]) async {
    final client = ref.read(builderCalendarClientProvider);
    if (client == null) return;
    Map<String, dynamic>? existing;
    try {
      if (id != null) existing = await client.event(id);
      if (!mounted) return;
      final input = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _EventEditor(event: existing, kk: _kk),
      );
      if (input == null || !mounted) return;
      if (id == null) {
        // This key belongs to this submission and survives the client's auth retry.
        await client.create(
          input,
          idempotencyKey: CraftAiClient.generateRequestId(),
        );
      } else {
        await client.replace(id, existing!['version'] as int, input);
      }
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_failure(error))));
      }
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text('Удалить событие?', 'Оқиғаны жою керек пе?')),
        content: Text(
          _text(
            'Повторяющееся событие будет удалено целиком.',
            'Қайталанатын оқиға толығымен жойылады.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_text('Отмена', 'Болдырмау')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_text('Удалить', 'Жою')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(builderCalendarClientProvider)!.delete(id);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_failure(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_text('Календарь Builder', 'Builder күнтізбесі')),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          tooltip: _text('Обновить', 'Жаңарту'),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _edit(),
      tooltip: _text('Создать событие', 'Оқиға жасау'),
      child: const Icon(Icons.add),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _text(
              'События хранятся на сервере CraftAI и удаляются с аккаунтом. Не указывайте персональные данные учеников.',
              'Оқиғалар CraftAI серверінде сақталады және аккаунтпен бірге жойылады. Оқушылардың жеке деректерін жазбаңыз.',
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: _text('Предыдущий месяц', 'Алдыңғы ай'),
              onPressed: () {
                _month = DateTime(_month.year, _month.month - 1);
                _load();
              },
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${_month.month.toString().padLeft(2, '0')}.${_month.year}'),
            IconButton(
              tooltip: _text('Следующий месяц', 'Келесі ай'),
              onPressed: () {
                _month = DateTime(_month.year, _month.month + 1);
                _load();
              },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
              ? Center(
                  child: Text(
                    _text(
                      'В этом месяце нет событий.',
                      'Бұл айда оқиғалар жоқ.',
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return ListTile(
                        title: Text(item['title'] as String),
                        subtitle: Text(
                          '${item['start']} — ${item['end']}\n${item['timeZone'] ?? _text('Весь день', 'Күні бойы')}',
                        ),
                        isThreeLine: true,
                        onTap: () => _edit(item['eventId'] as String),
                        trailing: IconButton(
                          tooltip: _text('Удалить', 'Жою'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(item['eventId'] as String),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}

class _EventEditor extends StatefulWidget {
  const _EventEditor({this.event, required this.kk});
  final Map<String, dynamic>? event;
  final bool kk;
  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _start, _end, _zone, _notes;
  late bool _allDay;
  String t(String ru, String kk) => widget.kk ? kk : ru;
  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final date = DateTime.now().toIso8601String().substring(0, 10);
    _title = TextEditingController(text: event?['title'] as String? ?? '');
    _start = TextEditingController(
      text: event?['start'] as String? ?? '${date}T09:00:00',
    );
    _end = TextEditingController(
      text: event?['end'] as String? ?? '${date}T10:00:00',
    );
    _zone = TextEditingController(
      text: event?['timeZone'] as String? ?? 'Asia/Almaty',
    );
    _notes = TextEditingController(text: event?['notes'] as String? ?? '');
    _allDay = event?['allDay'] as bool? ?? false;
  }

  @override
  void dispose() {
    for (final controller in [_title, _start, _end, _zone, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _time(String? value) {
    final pattern = _allDay
        ? r'^\d{4}-\d{2}-\d{2}$'
        : r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$';
    if (value == null ||
        !RegExp(pattern).hasMatch(value) ||
        DateTime.tryParse(value) == null) {
      return _allDay ? 'YYYY-MM-DD' : 'YYYY-MM-DDTHH:mm:ss';
    }
    final start = DateTime.tryParse(_start.text);
    final end = DateTime.tryParse(_end.text);
    if (start != null &&
        end != null &&
        (end.isBefore(start) || (!_allDay && end == start))) {
      return t(
        'Конец должен быть после начала.',
        'Аяқталуы басталуынан кейін болуы керек.',
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t('Событие', 'Оқиға')),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                maxLength: 200,
                decoration: InputDecoration(labelText: t('Название', 'Атауы')),
                validator: (v) => v == null || v.trim().isEmpty
                    ? t('Введите название', 'Атауын енгізіңіз')
                    : null,
              ),
              SwitchListTile(
                title: Text(t('Весь день', 'Күні бойы')),
                value: _allDay,
                onChanged: (value) => setState(() {
                  _allDay = value;
                  for (final controller in [_start, _end]) {
                    if (value && controller.text.length >= 10) {
                      controller.text = controller.text.substring(0, 10);
                    } else if (!value && controller.text.length == 10) {
                      controller.text += 'T09:00:00';
                    }
                  }
                }),
              ),
              TextFormField(
                controller: _start,
                decoration: InputDecoration(labelText: t('Начало', 'Басталуы')),
                validator: _time,
              ),
              TextFormField(
                controller: _end,
                decoration: InputDecoration(labelText: t('Конец', 'Аяқталуы')),
                validator: _time,
              ),
              if (!_allDay)
                TextFormField(
                  controller: _zone,
                  decoration: InputDecoration(
                    labelText: t('Часовой пояс IANA', 'IANA уақыт белдеуі'),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? t('Укажите пояс', 'Уақыт белдеуін көрсетіңіз')
                      : null,
                ),
              TextFormField(
                controller: _notes,
                maxLength: 1000,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: t('Заметки', 'Жазбалар'),
                ),
              ),
              if (widget.event?['recurrence'] != null)
                Text(
                  t(
                    'Правка применяется ко всей серии. Правило повторения сохранится.',
                    'Өңдеу бүкіл топтамаға қолданылады. Қайталау ережесі сақталады.',
                  ),
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
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, <String, dynamic>{
            'title': _title.text.trim(),
            'notes': _notes.text.trim(),
            'allDay': _allDay,
            'start': _start.text,
            'end': _end.text,
            'timeZone': _allDay ? null : _zone.text.trim(),
            'recurrence': widget.event?['recurrence'],
            'reminders': widget.event?['reminders'] ?? <int>[],
            'subject': widget.event?['subject'],
            'grade': widget.event?['grade'],
          });
        },
        child: Text(t('Сохранить на сервере', 'Серверде сақтау')),
      ),
    ],
  );
}
