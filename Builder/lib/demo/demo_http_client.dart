import 'dart:convert';

import 'package:http/http.dart' as http;

/// A local transport: no socket, API key, database or remote model is used.
class DemoHttpClient extends http.BaseClient {
  static const ownerId = 'demo-user';
  static const models = ['Демо · Учитель', 'Демо · Проверка'];
  final _agents = <String, Map<String, dynamic>>{};
  final _materials = <String, List<Map<String, dynamic>>>{};
  final _memory = <String, List<Map<String, dynamic>>>{};
  final _skills = <String, List<Map<String, dynamic>>>{};
  final _runs = <String, Map<String, dynamic>>{};
  final _idempotency = <String, String>{};
  int _sequence = 0;

  DemoHttpClient() {
    _create({
      'name': 'Математика · 5 класс',
      'subject': 'Математика',
      'grade': '5',
      'task_type': 'prepare_tasks',
      'model_id': models[0],
      'instruction':
          'Готовь три задания по дробям: от простого к сложному. Добавляй ответы и критерии проверки.',
    }, id: 'demo-math');
    _create({
      'name': 'Русский язык · 7 класс',
      'subject': 'Русский язык',
      'grade': '7',
      'task_type': 'check_answer',
      'model_id': models[1],
      'instruction':
          'Помогай проверять ответы по теме «Причастие». Объясняй исправления доброжелательно.',
    }, id: 'demo-russian');
    _add('demo-math', 'materials', {
      'title': 'Дроби: памятка',
      'content':
          'Чтобы сложить дроби с одинаковыми знаменателями, сложи числители, а знаменатель оставь прежним. Пример: 1/7 + 2/7 = 3/7.',
    });
    _add('demo-russian', 'materials', {
      'title': 'Причастие: памятка',
      'content':
          'Причастие обозначает признак предмета по действию. Пример: читающий ученик. Вопрос: какой?',
    });
    _add('demo-math', 'memory', {
      'content': 'В учебном примере нужны задания трёх уровней сложности.',
    });
    _add('demo-russian', 'memory', {
      'content':
          'В учебном примере сначала объясняем правило, затем предлагаем исправление.',
    });
  }

  String _id(String prefix) => '$prefix-${++_sequence}';
  String get _now => DateTime.now().toUtc().toIso8601String();
  Map<String, dynamic> _clone(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  Map<String, dynamic> _agent(String id) =>
      _agents[id] ?? (throw const _DemoError(404, 'agents.not-found'));

  Map<String, dynamic> _create(Map<String, dynamic> config, {String? id}) {
    if (_agents.length >= 5) {
      throw const _DemoError(409, 'agents.limit-reached');
    }
    final name = (config['name'] as String? ?? '').trim();
    if (name.isEmpty ||
        name.runes.length > 200 ||
        (config['instruction'] as String? ?? '').runes.length > 5000) {
      throw const _DemoError(422, 'request.invalid');
    }
    final agentId = id ?? _id('agent');
    final agent = <String, dynamic>{
      'task_type': 'custom',
      'subject': '',
      'grade': '',
      'instruction': '',
      'model_id': models[0],
      'permissions': {'save_material': true, 'search_materials': true},
      'skills': [],
      ..._clone(config),
      'name': name,
      'id': agentId,
      'epoch': 0,
      'version': 1,
      'version_id': '$agentId:1',
      'created_at': _now,
      'updated_at': _now,
    };
    _agents[agentId] = agent;
    _materials[agentId] = [];
    _memory[agentId] = [];
    _skills[agentId] = [
      {
        'slug': 'prepare_tasks',
        'title': 'Подготовка заданий',
        'version': '1',
        'base_content': 'Разделяй условие, ответ и критерии проверки.',
        'enabled': true,
        'override_text': '',
        'revision': 1,
        'collisions': <String>[],
      },
    ];
    return agent;
  }

  Map<String, dynamic> _update(String id, Map<String, dynamic> changes) {
    final agent = _agent(id);
    final next = {...agent, ..._clone(changes)};
    if ((next['name'] as String).trim().isEmpty ||
        (next['name'] as String).runes.length > 200 ||
        (next['instruction'] as String).runes.length > 5000) {
      throw const _DemoError(422, 'request.invalid');
    }
    next['version'] = (agent['version'] as int) + 1;
    next['version_id'] = '$id:${next['version']}';
    next['updated_at'] = _now;
    return _agents[id] = next;
  }

  Map<String, dynamic> _add(String id, String kind, Map<String, dynamic> body) {
    _agent(id);
    final content = body['content'] as String? ?? '';
    if (content.trim().isEmpty || content.runes.length > 10000) {
      throw const _DemoError(422, 'request.invalid');
    }
    final item = <String, dynamic>{
      ...body,
      'id': _id(kind),
      'agent_id': id,
      'source': 'text',
      'created_at_utc': _now,
    };
    (kind == 'materials' ? _materials : _memory)[id]!.add(item);
    return item;
  }

  void _clear(String id) {
    _materials[id]!.clear();
    _memory[id]!.clear();
    final invalid = _runs.entries
        .where((entry) => entry.value['agent_id'] == id)
        .map((entry) => entry.key)
        .toSet();
    _runs.removeWhere((key, _) => invalid.contains(key));
    _idempotency.removeWhere((_, value) => invalid.contains(value));
  }

  Map<String, dynamic> _event(
    Map<String, dynamic> run,
    String type,
    Map<String, dynamic> payload,
  ) => {
    'id': _id('event'),
    'sequence': (run['events'] as List).length + 1,
    'epoch': run['epoch'],
    'event_type': type,
    'payload': payload,
    'created_at_utc': _now,
  };

  String _answer(Map<String, dynamic> agent) {
    final instruction = (agent['instruction'] as String).toLowerCase();
    final brief =
        instruction.contains('кратк') || instruction.contains('коротк');
    final math = (agent['subject'] as String).toLowerCase().contains('математ');
    final text = math
        ? '1. Вычисли: 1/7 + 2/7. Ответ: 3/7.\n2. Найди разность: 5/9 − 2/9. Ответ: 1/3.\n3. У Маши осталось 3/8 пирога. Она съела 1/8. Сколько осталось? Ответ: 1/4.'
        : 'Пример: «Читающий ученик сидел у окна».\nПричастие — «читающий»: обозначает признак по действию и отвечает на вопрос «какой?».\nЗадание: найди причастие в предложении «На столе лежала прочитанная книга». Ответ: «прочитанная».';
    return 'ДЕМО: ответ по шаблону, без вызова ИИ.\n\n${brief ? text.split('\n').first : text}\n\nКритерий: верное решение и понятное объяснение.\nЧтобы показать подтверждение записи, отправьте «Сохрани материал». Для поиска — «Найди материалы».';
  }

  Map<String, dynamic> _startRun(
    String id,
    Map<String, dynamic> body,
    String key,
  ) {
    final agent = _agent(id);
    if (key.isEmpty) throw const _DemoError(422, 'request.invalid');
    final retryId = _idempotency['$id:$key'];
    if (retryId != null) return _runs[retryId]!;
    final prompt = (body['prompt'] as String? ?? '').trim();
    if (prompt.isEmpty) throw const _DemoError(422, 'request.invalid');
    final run = <String, dynamic>{
      'id': _id('run'),
      'agent_id': id,
      'epoch': agent['epoch'],
      'agent_version_id': agent['version_id'],
      'model_id': agent['model_id'] ?? models[0],
      'status': 'completed',
      'stop_reason': 'completed',
      'final_output': _answer(agent),
      'tool_calls_count': 0,
      'active_elapsed_ms': 0,
      'events': <Map<String, dynamic>>[],
      'pending_actions': <Map<String, dynamic>>[],
    };
    final events = run['events'] as List;
    events.add(
      _event(run, 'demo_started', {
        'mode': 'local_template',
        'instruction_characters': (agent['instruction'] as String).runes.length,
      }),
    );
    final permissions = agent['permissions'] as Map;
    if (prompt.toLowerCase().contains('сохран')) {
      if (permissions['save_material'] == true) {
        run['status'] = 'awaiting_confirmation';
        run['stop_reason'] = 'awaiting_confirmation';
        run['final_output'] =
            'ДЕМО: подтвердите сохранение учебного материала.';
        run['pending_actions'] = [
          {
            'id': _id('action'),
            'tool_call_id': _id('tool'),
            'tool_name': 'save_material',
            'params': {'title': 'Задания · демо', 'content': _answer(agent)},
            'params_hash': 'demo-local-only',
            'status': 'pending',
            'expires_at_utc': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 15))
                .toIso8601String(),
          },
        ];
        events.add(
          _event(run, 'confirmation_requested', {'tool_name': 'save_material'}),
        );
      } else {
        run['final_output'] =
            'ДЕМО: сохранение запрещено настройками агента. Включите save_material в настройках.';
        events.add(
          _event(run, 'tool_rejected', {'tool_name': 'save_material'}),
        );
      }
    } else if (prompt.toLowerCase().contains('найд') ||
        prompt.toLowerCase().contains('найти')) {
      if (permissions['search_materials'] == true) {
        final items = _materials[id]!;
        run['final_output'] =
            'ДЕМО: материалы этого агента:\n${items.isEmpty ? 'Материалов пока нет.' : items.map((item) => '${item['title']}: ${item['content']}').join('\n\n')}';
        run['tool_calls_count'] = 1;
        events.add(
          _event(run, 'tool_result', {
            'tool_name': 'search_materials',
            'result': {'count': items.length},
          }),
        );
      } else {
        run['final_output'] = 'ДЕМО: поиск запрещён настройками агента.';
        events.add(
          _event(run, 'tool_rejected', {'tool_name': 'search_materials'}),
        );
      }
    }
    _runs[run['id'] as String] = run;
    _idempotency['$id:$key'] = run['id'] as String;
    return run;
  }

  Object? _route(
    String method,
    List<String> path,
    Map<String, dynamic> body,
    String key,
  ) {
    if (path.isEmpty) throw const _DemoError(404, 'demo.not-found');
    if (path.first == 'runs' && path.length >= 2) {
      final run =
          _runs[path[1]] ?? (throw const _DemoError(404, 'runs.not-found'));
      if (method == 'GET' && path.length == 2) return run;
      final actions = run['pending_actions'] as List;
      if (method == 'POST' && path.length == 3 && path.last == 'cancel') {
        for (final action in actions) {
          action['status'] = 'cancelled';
        }
        run['status'] = 'cancelled';
        run['stop_reason'] = 'cancelled';
        return run;
      }
      if (method == 'POST' && path.length == 4 && path[2] == 'actions') {
        final action = actions
            .where((item) => item['id'] == path[3])
            .firstOrNull;
        if (action == null) throw const _DemoError(404, 'actions.not-found');
        if (action['status'] != 'pending') return run;
        if (!['approve', 'deny'].contains(body['decision'])) {
          throw const _DemoError(422, 'request.invalid');
        }
        if (DateTime.parse(
          action['expires_at_utc'] as String,
        ).isBefore(DateTime.now().toUtc())) {
          throw const _DemoError(409, 'action.expired');
        }
        action['status'] = body['decision'] == 'approve'
            ? 'approved'
            : 'denied';
        if (body['decision'] == 'approve') {
          final item = _add(
            run['agent_id'] as String,
            'materials',
            Map<String, dynamic>.from(action['params'] as Map),
          );
          run['tool_calls_count'] = 1;
          (run['events'] as List).add(
            _event(run, 'tool_result', {
              'tool_name': 'save_material',
              'result': {'material_id': item['id']},
            }),
          );
          run['final_output'] =
              'ДЕМО: материал сохранён. Его можно найти в настройках агента.';
        } else {
          run['final_output'] =
              'ДЕМО: сохранение отклонено. Материал не добавлен.';
        }
        run['status'] = 'completed';
        run['stop_reason'] = 'completed';
        return run;
      }
    }
    if (path.first != 'agents') throw const _DemoError(404, 'demo.not-found');
    if (path.length == 1) {
      if (method == 'GET') {
        return {'agents': _agents.values.toList(), 'limit': 5};
      }
      if (method == 'POST') return _create(body);
    }
    if (path.length < 2) throw const _DemoError(404, 'demo.not-found');
    final id = path[1];
    final agent = _agent(id);
    if (path.length == 2) {
      if (method == 'GET') return agent;
      if (method == 'PATCH') return _update(id, body);
      if (method == 'DELETE') {
        _clear(id);
        _agents.remove(id);
        _materials.remove(id);
        _memory.remove(id);
        _skills.remove(id);
        return null;
      }
    }
    if (path.length >= 3) {
      final resource = path[2];
      if (method == 'POST' && resource == 'copy') {
        final created = _create({
          ...agent,
          'name': body['name'] ?? '${agent['name']} — копия',
        });
        _skills[created['id']] = _skills[id]!.map(_clone).toList();
        return created;
      }
      if (method == 'POST' && resource == 'reset') {
        _clear(id);
        agent['epoch'] = (agent['epoch'] as int) + 1;
        return agent;
      }
      if (method == 'POST' && resource == 'runs') {
        return _startRun(id, body, key);
      }
      if (resource == 'materials' || resource == 'memory') {
        final items = (resource == 'materials' ? _materials : _memory)[id]!;
        if (method == 'GET' && path.length == 3) return {'items': items};
        if (method == 'POST' && path.length == 3) {
          return _add(id, resource, body);
        }
        if (method == 'DELETE' && path.length == 4) {
          items.removeWhere((item) => item['id'] == path[3]);
          return null;
        }
      }
      if (resource == 'skills') {
        if (method == 'GET') return {'items': _skills[id]};
        if (method == 'PUT' && path.length == 4) {
          final skill = _skills[id]!
              .where((item) => item['slug'] == path[3])
              .firstOrNull;
          if (skill == null) throw const _DemoError(404, 'skills.not-found');
          skill.addAll({
            'enabled': body['enabled'],
            'override_text': body['override_text'],
            'revision': (skill['revision'] as int) + 1,
          });
          _update(id, {
            'permissions': {
              'save_material': body['allow_save'],
              'search_materials': body['allow_search'],
            },
          });
          return skill;
        }
      }
    }
    throw const _DemoError(404, 'demo.not-found');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    Object? result;
    var status = 200;
    try {
      if (request.url.host != 'demo.invalid' ||
          !request.url.path.startsWith('/lab/v1/')) {
        throw const _DemoError(404, 'demo.local-only');
      }
      final body = bytes.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      result = _route(
        request.method,
        request.url.pathSegments.skip(2).toList(),
        body,
        request.headers['Idempotency-Key'] ?? '',
      );
      if (result == null) status = 204;
    } on _DemoError catch (error) {
      status = error.status;
      result = {
        'code': error.code,
        'message': 'Демо: действие недоступно или данные некорректны.',
      };
    }
    return http.StreamedResponse(
      Stream.value(status == 204 ? <int>[] : utf8.encode(jsonEncode(result))),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

class _DemoError implements Exception {
  const _DemoError(this.status, this.code);
  final int status;
  final String code;
}
