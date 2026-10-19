import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../models/model_providers.dart';
import '../../models/infrastructure/craft_ai_client.dart';
import '../../session/session_repository.dart';
import '../infrastructure/builder_schedules_client.dart';
import 'schedule_editor.dart';
import 'schedule_labels.dart';
import '../push/push_settings_card.dart';

final builderSchedulesClientProvider = Provider<BuilderSchedulesClient?>((ref) {
  final api = ref.watch(craftAiClientProvider);
  return api == null ? null : BuilderSchedulesClient(api);
});

class SchedulesPage extends ConsumerStatefulWidget {
  const SchedulesPage({super.key, required this.ownerId, this.initialRunId});
  final String ownerId;
  final String? initialRunId;
  @override
  ConsumerState<SchedulesPage> createState() => _SchedulesPageState();
}

class _SchedulesPageState extends ConsumerState<SchedulesPage>
    with WidgetsBindingObserver {
  Timer? _pollTimer;
  bool _foreground = true;
  List<Json> _schedules = [];
  List<Json>? _runs;
  String? _scheduleId, _cursor, _error;
  bool _busy = false;
  bool _inFlight = false;
  int _generation = 0;
  int _operationGeneration = 0;
  bool get kk => Localizations.localeOf(context).languageCode == 'kk';
  String t(String ru, String kz) => kk ? kz : ru;
  bool get _authorized {
    final session = ref.read(sessionProvider).value;
    return session is AuthenticatedSession && session.ownerId == widget.ownerId;
  }

  BuilderSchedulesClient get client =>
      ref.read(builderSchedulesClientProvider)!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_refresh);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _pollTimer?.cancel();
    if (_foreground) _schedulePoll();
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    if (!mounted || !_foreground || !_authorized || _error != null) return;
    _pollTimer = Timer(const Duration(seconds: 10), () {
      if (ModalRoute.of(context)?.isCurrent != true) {
        _schedulePoll();
        return;
      }
      _perform(() async {
        final schedules = await client.list();
        if (!_alive) return;
        _schedules = schedules;
        final ids = <String>{
          for (final run in _runs ?? <Json>[])
            if (run['status'] == 'queued' ||
                run['status'] == 'running' ||
                run['delivery'] == 'pending')
              run['id'] as String,
        };
        for (final schedule in schedules) {
          if (schedule['id'] == _scheduleId && widget.initialRunId == null) {
            final last = schedule['lastRun'] as Map?;
            if (last != null &&
                !(_runs ?? <Json>[]).any((r) => r['id'] == last['runId'])) {
              ids.add(last['runId'] as String);
            }
          }
        }
        for (final id in ids) {
          final fresh = await client.run(id);
          if (!_alive) return;
          final exists = _runs!.any((r) => r['id'] == id);
          _runs = [
            if (!exists) fresh,
            for (final run in _runs!)
              if (run['id'] == id) fresh else run,
          ];
        }
      });
    });
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_inFlight ||
        !_authorized ||
        ref.read(builderSchedulesClientProvider) == null) {
      return;
    }
    final generation = _generation;
    _pollTimer?.cancel();
    _inFlight = true;
    _operationGeneration = generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted && generation == _generation && _authorized) {
        _error = e is CraftAiException && e.statusCode == 404
            ? t(
                'Результат недоступен: он мог быть удалён, срок хранения истёк или он принадлежит другому аккаунту.',
                'Нәтиже қолжетімсіз: ол жойылған, сақтау мерзімі өткен немесе басқа аккаунтқа тиесілі болуы мүмкін.',
              )
            : e is CraftAiException && e.statusCode == 412
            ? t(
                'Расписание изменилось. Обновите список и откройте редактор заново.',
                'Кесте өзгерді. Тізімді жаңартып, редакторды қайта ашыңыз.',
              )
            : e is CraftAiException && e.statusCode == 429
            ? t(
                'Лимит ручных проб исчерпан. Повторите позже.',
                'Қолмен тексеру шегі таусылды. Кейін қайталаңыз.',
              )
            : t(
                'Запрос не подтверждён. Обновите историю перед повторной пробой.',
                'Сұрау расталмады. Қайта тексермес бұрын тарихты жаңартыңыз.',
              );
      }
    } finally {
      _inFlight = false;
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
        });
        _schedulePoll();
      } else if (mounted && _authorized) {
        Future.microtask(_refresh);
      }
    }
  }

  bool get _alive =>
      mounted && _authorized && _operationGeneration == _generation;
  Future<void> _refresh() => _perform(() async {
    final schedules = await client.list();
    if (!_alive) return;
    _schedules = schedules;
    if (widget.initialRunId != null) {
      final run = await client.run(widget.initialRunId!);
      if (!_alive) return;
      _scheduleId = run['scheduleId'] as String;
      _runs = [run];
      return;
    }
    if (_scheduleId != null) await _history(_scheduleId!);
  });

  Future<void> _history(String id, {bool more = false}) async {
    final page = await client.runs(id, cursor: more ? _cursor : null);
    if (!_alive) return;
    _scheduleId = id;
    _runs = [
      if (more) ...?_runs,
      for (final r in page['items'] as List) Json.from(r as Map),
    ];
    _cursor = page['nextCursor'] as String?;
  }

  Future<void> _edit(String template, Json? schedule) async {
    final generation = _generation;
    final input = await Navigator.of(context).push<Json>(
      MaterialPageRoute(
        builder: (_) => ScheduleEditor(
          ownerId: widget.ownerId,
          template: template,
          schedule: schedule,
        ),
      ),
    );
    if (input == null || !_alive || generation != _generation) return;
    await _perform(() async {
      await client.save(template, input, version: schedule?['version'] as int?);
      final schedules = await client.list();
      if (_alive) _schedules = schedules;
    });
  }

  Future<bool> _confirmDelete({bool resultOnly = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            t(
              resultOnly
                  ? 'Удалить этот результат?'
                  : 'Удалить расписание и все результаты?',
              resultOnly
                  ? 'Осы нәтиже жойылсын ба?'
                  : 'Кесте мен барлық нәтижелер жойылсын ба?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Отмена', 'Бас тарту')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('Удалить', 'Жою')),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (_, next) {
      if (!_authorized) {
        _pollTimer?.cancel();
        _generation++;
        setState(() {
          _schedules = [];
          _runs = null;
          _scheduleId = null;
          _error = null;
          _busy = false;
        });
      } else {
        Future.microtask(_refresh);
      }
    });
    final available = ref.watch(builderSchedulesClientProvider) != null;
    final authorized = ref.watch(sessionProvider).value;
    final canShow =
        authorized is AuthenticatedSession &&
        authorized.ownerId == widget.ownerId;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('AI-расписания', 'AI кестелері')),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: t('Обновить', 'Жаңарту'),
          ),
        ],
      ),
      body: !canShow
          ? Center(child: Text(t('Войдите в аккаунт', 'Аккаунтқа кіріңіз')))
          : !available
          ? Center(child: Text(t('Сервер не настроен', 'Сервер бапталмаған')))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  t(
                    'Расписание выполняется на сервере. Результаты доступны здесь даже без push. Пауза останавливает будущие задания; текущий запуск может завершиться.',
                    'Кесте серверде орындалады. Нәтижелер push болмаса да осында қолжетімді. Үзіліс болашақ тапсырмаларды тоқтатады; ағымдағы іске қосу аяқталуы мүмкін.',
                  ),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (widget.initialRunId == null)
                  PushSettingsCard(ownerId: widget.ownerId),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (widget.initialRunId == null)
                  for (final template in ['daily-brief', 'idea-generator'])
                    _card(template),
                if (_runs != null) ...[
                  const Divider(),
                  Text(
                    t('История запусков', 'Іске қосу тарихы'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_runs!.isEmpty)
                    Text(t('Запусков пока нет', 'Әзірге іске қосылмаған')),
                  for (final run in _runs!) _runCard(run),
                  if (_cursor != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _perform(
                              () => _history(_scheduleId!, more: true),
                            ),
                      child: Text(t('Ещё', 'Тағы')),
                    ),
                ],
                if (widget.initialRunId != null)
                  for (final template in ['daily-brief', 'idea-generator'])
                    _card(template),
              ],
            ),
    );
  }

  Widget _card(String template) {
    final matches = _schedules.where((s) => s['template'] == template);
    final s = matches.isEmpty ? null : matches.first;
    final id = s?['id'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              template == 'daily-brief'
                  ? 'Daily Brief'
                  : t('Генератор идей', 'Идеялар генераторы'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (s != null)
              Text(
                '${s['enabled'] == true ? t('Включено', 'Қосылған') : t('Пауза', 'Үзіліс')} · ${s['timeZone']}\n${t('Следующий запуск', 'Келесі іске қосу')}: ${s['nextRunAtUtc'] ?? '—'}',
              ),
            if (s?['lastRun'] != null)
              Text(
                '${t('Последний запуск', 'Соңғы іске қосу')}: ${scheduleLabel(s!['lastRun']['status'] as String?, kk: kk)}',
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _edit(template, s),
                  child: Text(
                    s == null ? t('Создать', 'Құру') : t('Изменить', 'Өзгерту'),
                  ),
                ),
                if (id != null) ...[
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _perform(() async {
                            await client.pause(
                              id,
                              paused: s!['enabled'] == true,
                            );
                            final list = await client.list();
                            if (_alive) _schedules = list;
                          }),
                    child: Text(
                      s!['enabled'] == true
                          ? t('Пауза', 'Үзіліс')
                          : t('Включить', 'Қосу'),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _perform(() async {
                            final run = await client.runNow(id);
                            if (_alive) {
                              _scheduleId = id;
                              _runs = [run];
                              _cursor = null;
                            }
                          }),
                    child: Text(t('Ручная проба', 'Қолмен тексеру')),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _perform(() => _history(id)),
                    child: Text(t('История', 'Тарих')),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (!await _confirmDelete() || !_alive) return;
                            await _perform(() async {
                              await client.delete(id);
                              if (!_alive) return;
                              _runs = null;
                              _scheduleId = null;
                              _cursor = null;
                              final list = await client.list();
                              if (_alive) _schedules = list;
                            });
                          },
                    child: Text(t('Отключить и удалить', 'Өшіру және жою')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _runCard(Json run) {
    final result = run['status'] == 'succeeded' ? run['result'] as Map? : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('${run['id']}'),
            Text(
              '${t('Запуск', 'Іске қосу')}: ${scheduleLabel(run['status'] as String?, kk: kk)} · ${scheduleLabel(run['trigger'] as String?, kk: kk)}\n${run['scheduledForUtc']}',
            ),
            if (run['statusReason'] != null)
              Text(
                '${t('Причина', 'Себеп')}: ${scheduleLabel(run['statusReason'] as String?, kk: kk)}',
              ),
            Text(
              '${t('Доставка', 'Жеткізу')}: ${run['delivery'] == 'failed' ? t('Не удалось отправить уведомление', 'Хабарламаны жіберу мүмкін болмады') : scheduleLabel(run['delivery'] as String?, kk: kk)}',
            ),
            if (result != null) ...[
              Text(
                '${t('Снимок источников', 'Деректер күйі')}: ${result['dataSnapshotAtUtc']}\n${t('Создано', 'Жасалған')}: ${result['generatedAtUtc']}',
              ),
              Text(
                t(
                  'Источники могли измениться после снимка.',
                  'Деректер сақталғаннан кейін өзгеруі мүмкін.',
                ),
              ),
              for (final source in result['sources'] as List)
                Text('${source['type']}: ${source['label']}'),
              for (final gap in result['gaps'] as List)
                Text('${t('Пробел данных', 'Деректердегі олқылық')}: $gap'),
              for (final section in result['sections'] as List) ...[
                Text(
                  section['title'] as String,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final item in section['items'] as List) Text('• $item'),
              ],
            ],
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _perform(() async {
                      final fresh = await client.run(run['id'] as String);
                      if (_alive) {
                        _runs = [
                          for (final r in _runs!)
                            if (r['id'] == fresh['id']) fresh else r,
                        ];
                      }
                    }),
              child: Text(t('Обновить запуск', 'Іске қосуды жаңарту')),
            ),
            if (run['status'] != 'queued' && run['status'] != 'running')
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final generation = _generation;
                        if (!await _confirmDelete(resultOnly: true) ||
                            !_alive ||
                            generation != _generation) {
                          return;
                        }
                        await _perform(() async {
                          await client.deleteRun(run['id'] as String);
                          if (!_alive) return;
                          _runs = [
                            for (final r in _runs!)
                              if (r['id'] != run['id']) r,
                          ];
                          final schedules = await client.list();
                          if (_alive) _schedules = schedules;
                        });
                      },
                child: Text(t('Удалить результат', 'Нәтижені жою')),
              ),
          ],
        ),
      ),
    );
  }
}
