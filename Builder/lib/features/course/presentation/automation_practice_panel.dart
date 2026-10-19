import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../calendar/infrastructure/reminder_scheduler.dart';
import '../../calendar/presentation/builder_calendar_page.dart';
import '../../schedules/presentation/schedules_page.dart';
import '../../schedules/infrastructure/builder_schedules_client.dart';
import '../../session/session_repository.dart';
import '../domain/automation_practice_evidence.dart';

/// Opens real product screens and reads evidence. Never grants course progress.
class AutomationPracticePanel extends ConsumerStatefulWidget {
  const AutomationPracticePanel({super.key, required this.ownerId});
  final String ownerId;
  @override
  ConsumerState<AutomationPracticePanel> createState() =>
      _AutomationPracticePanelState();
}

class _AutomationPracticePanelState
    extends ConsumerState<AutomationPracticePanel> {
  bool _loading = false;
  int _epoch = 0;
  String? _problem;
  DateTime? _checkedAt;
  ({
    bool enabled,
    ReminderPermission permission,
    int events,
    DateTime? syncedAt,
  })?
  _reminder;
  List<AutomationTemplateEvidence> _evidence = [];
  bool get kk => Localizations.localeOf(context).languageCode == 'kk';
  String t(String ru, String kz) => kk ? kz : ru;
  bool get _authorized {
    final session = ref.read(sessionProvider).value;
    return session is AuthenticatedSession && session.ownerId == widget.ownerId;
  }

  Future<void> _open(Widget page) async {
    final epoch = _epoch;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted && _authorized && epoch == _epoch) await _readEvidence();
  }

  Future<void> _readEvidence() async {
    if (_loading || !_authorized) return;
    final epoch = _epoch;
    bool current() => mounted && _authorized && epoch == _epoch;
    setState(() {
      _loading = true;
      _problem = null;
      _checkedAt = null;
      _evidence = [];
      _reminder = null;
    });
    try {
      final api = ref.read(builderSchedulesClientProvider);
      if (api == null) {
        setState(
          () => _problem = t(
            'Сервер не настроен. Данные запусков недоступны.',
            'Сервер бапталмаған. Іске қосу деректері қолжетімсіз.',
          ),
        );
        return;
      }
      // Read configuration only: checking evidence must never re-plan notifications.
      final repository = ref.read(calendarRepositoryProvider);
      final enabled = await repository.remindersEnabled(widget.ownerId);
      if (!current()) return;
      final permission = await ref.read(reminderSchedulerProvider).permission();
      if (!current()) return;
      final events = await repository.events(widget.ownerId);
      if (!current()) return;
      final syncedAt = await repository.syncedAt(widget.ownerId);
      if (!current()) return;
      _reminder = (
        enabled: enabled,
        permission: permission,
        events: events.where((e) => e.reminders.isNotEmpty).length,
        syncedAt: syncedAt,
      );
      final schedules = await api.list();
      if (!current()) return;
      final evidence = <AutomationTemplateEvidence>[];
      for (final template in ['daily-brief', 'idea-generator']) {
        final matches = schedules.where((s) => s['template'] == template);
        if (matches.isEmpty) {
          evidence.add(AutomationTemplateEvidence(template: template));
          continue;
        }
        final schedule = matches.first;
        final runs = <Json>[];
        String? cursor;
        final seenCursors = <String>{};
        do {
          final page = await api.runs(schedule['id'] as String, cursor: cursor);
          if (!current()) return;
          runs.addAll([
            for (final run in page['items'] as List) Json.from(run as Map),
          ]);
          cursor = page['nextCursor'] as String?;
          // At most 30 retained results per schedule; guard malformed pagination.
          if (cursor != null &&
              (!seenCursors.add(cursor) || seenCursors.length > 3)) {
            throw const FormatException('Invalid history pagination');
          }
        } while (cursor != null);
        evidence.add(
          AutomationTemplateEvidence.fromHistory(template, schedule, runs),
        );
      }
      if (!current()) return;
      setState(() {
        _evidence = evidence;
        _checkedAt = DateTime.now();
      });
    } catch (_) {
      if (current()) {
        setState(() {
          _evidence = [];
          _checkedAt = null;
          _problem = t(
            'Не удалось получить подтверждения. Обновите данные; практика не засчитана.',
            'Растайтын деректер алынбады. Деректерді жаңартыңыз; тәжірибе есептелмеді.',
          );
        });
      }
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (_, next) {
      if (!_authorized) {
        _epoch++;
        setState(() {
          _loading = false;
          _evidence = [];
          _reminder = null;
          _checkedAt = null;
          _problem = null;
        });
      }
    });
    final session = ref.watch(sessionProvider).value;
    if (session is! AuthenticatedSession || session.ownerId != widget.ownerId) {
      return Text(
        t(
          'Для практики войдите в свой аккаунт.',
          'Тәжірибе үшін өз аккаунтыңызға кіріңіз.',
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Выполнить в приложении', 'Қосымшада орындау'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              t(
                'Эти кнопки открывают ваши настоящие данные. Создание, проба, пауза и удаление выполняются только по вашему действию на соответствующем экране.',
                'Бұл түймелер өз деректеріңізді ашады. Құру, тексеру, үзіліс және жою тиісті экранда тек өз әрекетіңізбен орындалады.',
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _loading
                      ? null
                      : () =>
                            _open(BuilderCalendarPage(ownerId: widget.ownerId)),
                  child: Text(t('Открыть календарь', 'Күнтізбені ашу')),
                ),
                OutlinedButton(
                  onPressed: _loading
                      ? null
                      : () => _open(SchedulesPage(ownerId: widget.ownerId)),
                  child: Text(t('Открыть AI-расписания', 'AI кестелерін ашу')),
                ),
                OutlinedButton(
                  onPressed: _loading ? null : _readEvidence,
                  child: Text(
                    t('Обновить подтверждения', 'Растайтын деректерді жаңарту'),
                  ),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_problem != null)
              Text(
                _problem!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_reminder != null) ...[
              Text(
                _reminder!.enabled &&
                        _reminder!.permission == ReminderPermission.granted &&
                        _reminder!.events > 0
                    ? t(
                        'Напоминания включены, разрешение есть. Событий с напоминанием в кэше: ${_reminder!.events}. Это не подтверждает постановку или показ уведомления.',
                        'Еске салулар қосылған, рұқсат бар. Кэштегі еске салуы бар оқиға саны: ${_reminder!.events}. Бұл хабарламаның жоспарланғанын немесе көрсетілгенін растамайды.',
                      )
                    : t(
                        'Настройка напоминаний не подтверждена. Проверьте событие, разрешение и ближайшие даты в календаре.',
                        'Еске салу баптауы расталмады. Күнтізбедегі оқиғаны, рұқсатты және жақын күндерді тексеріңіз.',
                      ),
              ),
              Text(
                '${t('Календарь синхронизирован', 'Күнтізбе синхрондалған')}: ${_reminder!.syncedAt ?? '—'}',
              ),
            ],
            if (_checkedAt != null)
              Text(
                t(
                  'Данные прочитаны: $_checkedAt',
                  'Деректер оқылды: $_checkedAt',
                ),
              ),
            for (final evidence in _evidence) ...[
              const SizedBox(height: 12),
              Text(
                evidence.template == 'daily-brief'
                    ? 'Daily Brief'
                    : t('Генератор идей', 'Идеялар генераторы'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (evidence.scheduleId == null)
                Text(t('Расписание не найдено.', 'Кесте табылмады.')),
              _run(t('Ручная проба', 'Қолмен тексеру'), evidence.manualRun),
              _run(t('По расписанию', 'Кесте бойынша'), evidence.scheduledRun),
            ],
            Text(
              t(
                'Это сведения из сохранённой истории, а не зачёт. Удалённые и истёкшие результаты здесь не подтверждаются. Показ напоминания, качество ответа и действия паузы/отключения нужно проверить отдельно. Учебный прогресс не изменяется.',
                'Бұл — сақталған тарих деректері, бағалау емес. Жойылған және мерзімі өткен нәтижелер мұнда расталмайды. Еске салудың көрсетілуін, жауап сапасын және үзіліс/өшіру әрекеттерін бөлек тексеру керек. Оқу үлгерімі өзгермейді.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _run(String label, Json? run) {
    if (run == null) {
      return Text(
        '$label: ${t('готовый результат не найден', 'дайын нәтиже табылмады')}',
      );
    }
    final result = run['result'] as Map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ${t('есть сохранённый результат', 'сақталған нәтиже бар')}',
        ),
        SelectableText('${run['id']}'),
        Text(
          '${t('Создано', 'Жасалған')}: ${result['generatedAtUtc']}\n${t('Снимок данных', 'Деректер күйі')}: ${result['dataSnapshotAtUtc']}',
        ),
        for (final gap in result['gaps'] as List? ?? [])
          Text('${t('Пробел данных', 'Деректердегі олқылық')}: $gap'),
        ExpansionTile(
          title: Text(
            t('Посмотреть сохранённый ответ', 'Сақталған жауапты көру'),
          ),
          children: [
            for (final source in result['sources'] as List? ?? [])
              if (source is Map && source['label'] is String)
                Text(source['label'] as String),
            for (final section in result['sections'] as List)
              if (section is Map)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (section['title'] is String)
                        Text(
                          section['title'] as String,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      for (final item in section['items'] as List? ?? [])
                        if (item is String) Text('• $item'),
                    ],
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
