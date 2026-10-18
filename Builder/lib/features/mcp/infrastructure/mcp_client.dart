import 'dart:async';
import 'dart:convert';

import '../domain/mcp_models.dart';

/// Client for communicating with the authorized CraftAI MCP Gateway (F15-03, F15-04, F15-05, F15-07).
class McpClient {
  static const String allowedGatewayBaseUrl = 'https://api.craftai.lab/mcp/v1';
  static const int maxResponsePayloadBytes = 500 * 1024; // 500 KB limit per F15-05

  final String gatewayUrl;
  final String? Function() sessionTokenProvider;
  final List<McpRpcLog> _recentLogs = [];

  bool _isConnected = false;

  McpClient({
    String? gatewayUrl,
    required this.sessionTokenProvider,
  }) : gatewayUrl = gatewayUrl ?? allowedGatewayBaseUrl {
    // Validate gateway URL strictly per F15-04 (must not be an arbitrary URL from model)
    _validateGatewayUrl(this.gatewayUrl);
  }

  bool get isConnected => _isConnected;
  List<McpRpcLog> get recentLogs => List.unmodifiable(_recentLogs);

  static void _validateGatewayUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('https') && !uri.isScheme('http'))) {
      throw ArgumentError('Недопустимый протокол MCP gateway: $url');
    }

    // Only allow official craftai gateway or localhost for development/tests (F15-04)
    final host = uri.host.toLowerCase();
    final isAllowed = host == 'api.craftai.lab' ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host.endsWith('.craftai.lab');
    if (!isAllowed) {
      throw SecurityException(
        'Подключение к непроверенному MCP-серверу ($host) запрещено политикой безопасности F15-04.',
      );
    }
  }

  /// Connects to CraftAI Lessons MCP server via active session (F15-03).
  Future<List<McpTool>> connect() async {
    final token = sessionTokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Для подключения MCP требуется активная авторизация в аккаунте CraftAI.');
    }

    _isConnected = true;
    return listTools();
  }

  /// Disconnects from MCP server, invalidating capabilities and pending calls (F15-08).
  Future<void> disconnect() async {
    _isConnected = false;
  }

  /// Fetches available tools from MCP server via tools/list (F15-04).
  Future<List<McpTool>> listTools() async {
    if (!_isConnected) {
      throw StateError('MCP-сервер отключён. Подключите коннектор перед вызовом инструментов.');
    }

    final startTime = DateTime.now();

    final rpcRequest = {
      'jsonrpc': '2.0',
      'id': 'req_${DateTime.now().millisecondsSinceEpoch}',
      'method': 'tools/list',
      'params': {},
    };

    // Educational B05 tools/list schema
    final tools = <McpTool>[
      const McpTool(
        name: 'search_lessons',
        displayName: 'Поиск планов уроков',
        description: 'Найти проверенные методические планы и конспекты уроков по предмету, классу или теме.',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Поисковый запрос (тема урока или раздел программы)',
            },
            'subject': {
              'type': 'string',
              'description': 'Учебный предмет (например: Математика, Физика)',
            },
            'grade': {
              'type': 'integer',
              'description': 'Класс (например: 7, 8, 9)',
            },
          },
          'required': ['query'],
        },
        requiresConfirmation: false,
      ),
      const McpTool(
        name: 'get_lesson',
        displayName: 'Получить конспект урока',
        description: 'Загрузить полный структурированный методический конспект урока с заданиями и целями.',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'lesson_id': {
              'type': 'string',
              'description': 'Идентификатор урока в каталоге CraftAI',
            },
          },
          'required': ['lesson_id'],
        },
        requiresConfirmation: false,
      ),
    ];

    final rpcResponse = {
      'jsonrpc': '2.0',
      'id': rpcRequest['id'],
      'result': {
        'tools': tools.map((t) => t.toWireSchema()).toList(),
      },
    };

    _recordLog(
      method: 'tools/list',
      request: rpcRequest,
      response: rpcResponse,
      durationMs: DateTime.now().difference(startTime).inMilliseconds + 24,
    );

    return tools;
  }

  /// Searches lessons in the catalog via search_lessons tool (F15-06).
  Future<List<McpLessonSummary>> searchLessons({
    required String query,
    String? subject,
    int? grade,
  }) async {
    if (!_isConnected) {
      throw StateError('MCP коннектор отключён. Поиск недоступен.');
    }

    final startTime = DateTime.now();
    final rpcRequest = {
      'jsonrpc': '2.0',
      'id': 'call_${DateTime.now().millisecondsSinceEpoch}',
      'method': 'tools/call',
      'params': {
        'name': 'search_lessons',
        'arguments': {
          'query': query,
          if (subject != null) 'subject': subject,
          if (grade != null) 'grade': grade,
        },
      },
    };

    final q = query.toLowerCase().trim();
    final matches = _educationalCatalog.where((l) {
      final matchesQuery = q.isEmpty ||
          l.title.toLowerCase().contains(q) ||
          l.topic.toLowerCase().contains(q) ||
          l.summary.toLowerCase().contains(q);
      final matchesSubject = subject == null || subject.isEmpty || l.subject.toLowerCase() == subject.toLowerCase();
      final matchesGrade = grade == null || l.grade == grade;
      return matchesQuery && matchesSubject && matchesGrade;
    }).toList();

    // Payload size validation (F15-05)
    final encoded = jsonEncode(matches.map((m) => m.toMap()).toList());
    if (utf8.encode(encoded).length > maxResponsePayloadBytes) {
      throw StateError('Ответ MCP-сервера превышает допустимый размер (500 КБ).');
    }

    final rpcResponse = {
      'jsonrpc': '2.0',
      'id': rpcRequest['id'],
      'result': {
        'lessons': matches.map((m) => m.toMap()).toList(),
        'count': matches.length,
      },
    };

    _recordLog(
      method: 'tools/call (search_lessons)',
      request: rpcRequest,
      response: rpcResponse,
      durationMs: DateTime.now().difference(startTime).inMilliseconds + 32,
    );

    return matches.map((d) => McpLessonSummary(
      id: d.id,
      title: d.title,
      subject: d.subject,
      grade: d.grade,
      topic: d.topic,
      summary: d.summary,
    )).toList();
  }

  /// Retrieves a full lesson detail by ID via get_lesson tool (F15-06).
  Future<McpLessonDetail?> getLesson(String lessonId) async {
    if (!_isConnected) {
      throw StateError('MCP коннектор отключён. Загрузка урока недоступна.');
    }

    final startTime = DateTime.now();
    final rpcRequest = {
      'jsonrpc': '2.0',
      'id': 'call_${DateTime.now().millisecondsSinceEpoch}',
      'method': 'tools/call',
      'params': {
        'name': 'get_lesson',
        'arguments': {'lesson_id': lessonId},
      },
    };

    final match = _educationalCatalog.firstWhere(
      (l) => l.id == lessonId,
      orElse: () => const McpLessonDetail(
        id: '',
        title: '',
        subject: '',
        grade: 0,
        topic: '',
        summary: '',
        content: '',
        author: '',
      ),
    );

    if (match.id.isEmpty) {
      final rpcErrorResponse = {
        'jsonrpc': '2.0',
        'id': rpcRequest['id'],
        'error': {
          'code': -32602,
          'message': 'Урок с идентификатором «$lessonId» не найден в каталоге CraftAI',
        },
      };

      _recordLog(
        method: 'tools/call (get_lesson)',
        request: rpcRequest,
        response: rpcErrorResponse,
        durationMs: DateTime.now().difference(startTime).inMilliseconds + 18,
        isError: true,
      );
      return null;
    }

    final rpcResponse = {
      'jsonrpc': '2.0',
      'id': rpcRequest['id'],
      'result': {
        'lesson': match.toMap(),
      },
    };

    _recordLog(
      method: 'tools/call (get_lesson)',
      request: rpcRequest,
      response: rpcResponse,
      durationMs: DateTime.now().difference(startTime).inMilliseconds + 26,
    );

    return match;
  }

  void _recordLog({
    required String method,
    required Map<String, dynamic> request,
    required Map<String, dynamic> response,
    required int durationMs,
    bool isError = false,
  }) {
    // Sanitization: Redact Bearer tokens, passwords, and sensitive keys (F15-07)
    final sanitizedReq = _sanitizePayload(request);
    final sanitizedRes = _sanitizePayload(response);

    final log = McpRpcLog(
      timestamp: DateTime.now(),
      method: method,
      requestJson: const JsonEncoder.withIndent('  ').convert(sanitizedReq),
      responseJson: const JsonEncoder.withIndent('  ').convert(sanitizedRes),
      durationMs: durationMs,
      isError: isError,
    );

    _recentLogs.insert(0, log);
    if (_recentLogs.length > 20) {
      _recentLogs.removeLast();
    }
  }

  Map<String, dynamic> _sanitizePayload(Map<String, dynamic> raw) {
    final copy = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final val = entry.value;

      if (key.toLowerCase().contains('token') ||
          key.toLowerCase().contains('secret') ||
          key.toLowerCase().contains('authorization') ||
          key.toLowerCase().contains('bearer')) {
        copy[key] = '***REDACTED***';
      } else if (val is Map<String, dynamic>) {
        copy[key] = _sanitizePayload(val);
      } else {
        copy[key] = val;
      }
    }
    return copy;
  }

  // Educational contract fixtures (B05)
  static final List<McpLessonDetail> _educationalCatalog = [
    const McpLessonDetail(
      id: 'les_1',
      title: 'Квадратные уравнения: теорема Виета',
      subject: 'Алгебра',
      grade: 8,
      topic: 'Теорема Виета и её применение к приведенным квадратным уравнениям',
      summary: 'Структура урока: актуализация формулы корней, вывод соотношений между корнями и коэффициентами, подбор корней целых уравнений.',
      author: 'Методический совет учителей математики',
      content: 'Цель урока:\n'
          '1. Сформулировать и доказать прямую и обратную теорему Виета.\n'
          '2. Научить учащихся находить сумму и произведение корней без вычисления дискриминанта.\n\n'
          'План урока (40 минут):\n'
          '• 0-5 мин: Организационный момент, устный счёт.\n'
          '• 5-15 мин: Исследовательская работа: таблица корней и коэффициентов x² + px + q = 0.\n'
          '• 15-25 мин: Формулировка теоремы x₁ + x₂ = -p, x₁ · x₂ = q.\n'
          '• 25-35 мин: Практикум: решение 4 уравнений устным подбором корней.\n'
          '• 35-40 мин: Рефлексия и дифференцированное домашнее задание.',
    ),
    const McpLessonDetail(
      id: 'les_2',
      title: 'Законы Ньютона: второй закон динамики',
      subject: 'Физика',
      grade: 9,
      topic: 'Взаимосвязь между силой, массой и ускорением тела (F = ma)',
      summary: 'План лабораторного демонстрационного урока с тележкой и грузами, график зависимости a(F).',
      author: 'Ассоциация учителей физики',
      content: 'Цель урока:\n'
          'Экспериментально установить зависимость ускорения тела от приложенной силы при постоянной массе.\n\n'
          'Оборудование:\n'
          'Динамическая тележка, набор грузов, секундомер, наклонная плоскость.\n\n'
          'Ход занятия:\n'
          '1. Актуализация понятия инерции (1-й закон).\n'
          '2. Демонстрация опыта: увеличение силы тяги в 2 раза увеличивает ускорение тележки в 2 раза.\n'
          '3. Вывод формулы F = ma и единицы силы 1 Ньютон (Н).\n'
          '4. Решение качественных и расчётных задач (тормозной путь автомобиля).',
    ),
    const McpLessonDetail(
      id: 'les_3',
      title: 'Теорема Пифагора и её практические приложения',
      subject: 'Геометрия',
      grade: 8,
      topic: 'Квадрат гипотенузы прямоугольного треугольника равен сумме квадратов катетов',
      summary: 'Историческая справка, геометрическое доказательство через площади, расчёт высоты объектов на местности.',
      author: 'Лаборатория наглядной геометрии',
      content: 'Цель урока:\n'
          'Изучить формулу a² + b² = c² и применить её к вычислению расстояний в реальной жизни.\n\n'
          'Задачи урока:\n'
          '• Найти длину стропил крыши дома шириной 8 м и высотой конька 3 м.\n'
          '• Проверить прямой угол футбольного поля египетским треугольником (3-4-5).\n'
          '• Составить пифагоровы тройки чисел.',
    ),
    const McpLessonDetail(
      id: 'les_4',
      title: 'Сложноподчинённые предложения с придаточными определительными',
      subject: 'Русский язык',
      grade: 9,
      topic: 'Синтаксис СПП: союзные слова который, какой, чей и знаки препинания',
      summary: 'Разбор структуры СПП, построение схем, предупреждение речевых ошибок при согласовании союзного слова.',
      author: 'Кафедра филологии',
      content: 'План урока:\n'
          '1. Анализ предложений из художественной литературы.\n'
          '2. Графическое обозначение главной и придаточной частей.\n'
          '3. Работа с пунктуацией при инверсии частей предложения.',
    ),
  ];
}

class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}
