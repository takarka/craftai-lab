import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../infrastructure/search_adapter.dart';
import 'tools_providers.dart';

/// Opens a result in the external browser; replaced in tests.
final searchLinkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

enum _Phase { idle, loading, results, failed }

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _query = TextEditingController();
  _Phase _phase = _Phase.idle;
  List<SearchHit> _hits = const [];
  SearchFailureKind? _failure;
  String _lastQuery = '';
  Completer<void>? _abort;
  int _generation = 0;

  bool get _kk => Localizations.localeOf(context).languageCode == 'kk';
  String _text(String ru, String kk) => _kk ? kk : ru;

  @override
  void dispose() {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final query = _query.text.trim();
    if (query.isEmpty || _phase == _Phase.loading) return;
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    final abort = Completer<void>();
    _abort = abort;
    setState(() {
      _phase = _Phase.loading;
      _lastQuery = query;
    });
    try {
      final hits = await ref
          .read(searchAdapterProvider)
          .search(query, abortTrigger: abort.future);
      if (!mounted || generation != _generation) return;
      setState(() {
        _hits = hits;
        _phase = _Phase.results;
      });
    } on SearchException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure = error.kind;
        _hits = const [];
        _phase = error.kind == SearchFailureKind.cancelled
            ? _Phase.idle
            : _Phase.failed;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure = SearchFailureKind.invalidResponse;
        _phase = _Phase.failed;
      });
    }
  }

  void _cancel() {
    final abort = _abort;
    if (abort == null || abort.isCompleted) return;
    // The request is aborted; a late answer is ignored through the generation.
    _generation++;
    abort.complete();
    setState(() => _phase = _Phase.idle);
  }

  Future<void> _open(SearchHit hit) async {
    final uri = SearchAdapter.safeLink(hit.url);
    if (uri == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text('Открыть ссылку?', 'Сілтемені ашу керек пе?')),
        content: Text(
          '${uri.host}\n\n$uri\n\n'
          '${_text('Сайт откроется во внешнем браузере. CraftAI не проверял его содержимое.', 'Сайт сыртқы браузерде ашылады. CraftAI оның мазмұнын тексермеген.')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_text('Отмена', 'Болдырмау')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_text('Открыть', 'Ашу')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var opened = false;
    try {
      opened = await ref.read(searchLinkOpenerProvider)(uri);
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text('Не удалось открыть ссылку.', 'Сілтемені ашу мүмкін болмады.'),
          ),
        ),
      );
    }
  }

  String _failureText(SearchFailureKind kind) => switch (kind) {
    SearchFailureKind.noNetwork => _text(
      'Нет соединения с CraftAI. Проверьте интернет и повторите.',
      'CraftAI-мен байланыс жоқ. Интернетті тексеріп, қайталаңыз.',
    ),
    SearchFailureKind.auth => _text(
      'Сессия истекла или доступ закрыт. Войдите в аккаунт заново.',
      'Сессия аяқталды немесе қолжетімділік жабық. Аккаунтқа қайта кіріңіз.',
    ),
    SearchFailureKind.rateLimited => _text(
      'Слишком много запросов. Подождите немного и повторите.',
      'Сұраныс тым көп. Сәл күтіп, қайталаңыз.',
    ),
    SearchFailureKind.unavailable => _text(
      'Поиск сейчас недоступен. Это сбой сервиса, а не пустая выдача. Повторите позже.',
      'Іздеу қазір қолжетімсіз. Бұл сервис ақауы, нәтиже бос емес. Кейінірек қайталаңыз.',
    ),
    SearchFailureKind.notConfigured => _text(
      'Поиск недоступен без входа в аккаунт.',
      'Аккаунтқа кірмей іздеу қолжетімсіз.',
    ),
    SearchFailureKind.invalidResponse => _text(
      'Сервер ответил в неожиданном формате. Повторите позже.',
      'Сервер күтпеген форматта жауап берді. Кейінірек қайталаңыз.',
    ),
    SearchFailureKind.cancelled => '',
  };

  @override
  Widget build(BuildContext context) {
    final loading = _phase == _Phase.loading;
    return Scaffold(
      appBar: AppBar(title: Text(_text('Поиск CraftAI', 'CraftAI іздеуі'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _text(
              'Запрос отправляется на сервер CraftAI и во внешний поисковый сервис. Не указывайте персональные данные учеников. Результаты — это тексты из интернета: относитесь к ним как к непроверенным.',
              'Сұраныс CraftAI серверіне және сыртқы іздеу қызметіне жіберіледі. Оқушылардың жеке деректерін жазбаңыз. Нәтижелер — интернеттегі мәтіндер: оларды тексерілмеген деп қараңыз.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _query,
            maxLength: 500,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              labelText: _text('Что искать', 'Не іздеу керек'),
            ),
          ),
          Row(
            children: [
              FilledButton.icon(
                onPressed: loading ? null : _run,
                icon: const Icon(Icons.search),
                label: Text(_text('Найти', 'Іздеу')),
              ),
              const SizedBox(width: 12),
              if (loading)
                OutlinedButton(
                  onPressed: _cancel,
                  child: Text(_text('Отменить', 'Болдырмау')),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (loading) const Center(child: CircularProgressIndicator()),
          if (_phase == _Phase.failed && _failure != null) ...[
            Text(_failureText(_failure!)),
            TextButton(
              onPressed: _run,
              child: Text(_text('Повторить', 'Қайталау')),
            ),
          ],
          if (_phase == _Phase.results && _hits.isEmpty)
            Text(
              _text(
                'По запросу «$_lastQuery» ничего не найдено. Измените формулировку.',
                '«$_lastQuery» бойынша ештеңе табылмады. Сұранысты өзгертіп көріңіз.',
              ),
            ),
          if (_phase == _Phase.results)
            for (final hit in _hits)
              Card(
                key: ValueKey(hit.url),
                child: ListTile(
                  title: Text(hit.title),
                  subtitle: Text(
                    '${hit.source}${hit.snippet.isEmpty ? '' : '\n${hit.snippet}'}',
                  ),
                  isThreeLine: hit.snippet.isNotEmpty,
                  trailing: IconButton(
                    tooltip: _text('Открыть источник', 'Дереккөзді ашу'),
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => _open(hit),
                  ),
                  onTap: () => _open(hit),
                ),
              ),
        ],
      ),
    );
  }
}
