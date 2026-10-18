import '../../../ui_kit/identity.dart';

/// MCP Connector status.
enum McpConnectionStatus {
  disconnected('Отключено'),
  connecting('Подключение...'),
  connected('Подключено'),
  comingSoon('Скоро');

  final String label;
  const McpConnectionStatus(this.label);
}

/// Description of an MCP connector (F15-01, F15-02, F15-10).
class McpConnector {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final bool isComingSoon;
  final String dataDisclosure;
  final BuilderGlyph glyph;
  final List<String> capabilities;

  const McpConnector({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    this.isComingSoon = false,
    required this.dataDisclosure,
    required this.glyph,
    this.capabilities = const [],
  });

  static const craftAiLessonsId = 'craftai_lessons';
  static const googleDriveId = 'google_drive';
  static const googleCalendarId = 'google_calendar';
  static const kundelikId = 'kundelik';

  static const List<McpConnector> allConnectors = [
    McpConnector(
      id: craftAiLessonsId,
      title: 'Каталог уроков CraftAI',
      subtitle: 'Методические материалы и готовые планы уроков',
      description:
          'Учебный MCP-сервер с базой проверенных методических планов уроков по математике, физике и другим школьным предметам.',
      isComingSoon: false,
      dataDisclosure:
          'Передаёт поисковые запросы по теме урока в каталог CraftAI. '
          'Возвращает тексты планов уроков и конспектов. Не передаёт персональные данные учеников.',
      glyph: BuilderGlyph.doc,
      capabilities: [
        'Поиск уроков по предмету и классу (search_lessons)',
        'Загрузка полного конспекта урока (get_lesson)',
      ],
    ),
    McpConnector(
      id: googleDriveId,
      title: 'Google Диск',
      subtitle: 'Школьные документы и рабочие программы',
      description:
          'Интеграция с личными и общими папками Google Drive для быстрого поиска учебных документов.',
      isComingSoon: true,
      dataDisclosure: 'Потребует авторизацию через аккаунт Google.',
      glyph: BuilderGlyph.cloud,
    ),
    McpConnector(
      id: googleCalendarId,
      title: 'Google Календарь',
      subtitle: 'Синхронизация школьного расписания',
      description:
          'Двусторонняя синхронизация уроков и консультаций с внешним Google Календарём.',
      isComingSoon: true,
      dataDisclosure:
          'Потребует доступ к просмотру и созданию событий в Google Calendar.',
      glyph: BuilderGlyph.calendar,
    ),
    McpConnector(
      id: kundelikId,
      title: 'Электронный журнал',
      subtitle: 'Темы уроков и расписание классов',
      description:
          'Интеграция со школьным журналом для чтения утверждённого поурочного планирования.',
      isComingSoon: true,
      dataDisclosure:
          'Потребует подключение к закрытому API школьного портала.',
      glyph: BuilderGlyph.doc,
    ),
  ];
}

/// Tool exposed by MCP gateway via tools/list (F15-04, F15-05).
class McpTool {
  final String name;
  final String displayName;
  final String description;
  final Map<String, dynamic> parametersSchema;
  final bool requiresConfirmation;

  const McpTool({
    required this.name,
    required this.displayName,
    required this.description,
    required this.parametersSchema,
    this.requiresConfirmation = false,
  });

  Map<String, dynamic> toWireSchema() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parametersSchema,
      },
    };
  }
}

/// Brief lesson summary item returned from search_lessons (F15-06).
class McpLessonSummary {
  final String id;
  final String title;
  final String subject;
  final int grade;
  final String topic;
  final String summary;

  const McpLessonSummary({
    required this.id,
    required this.title,
    required this.subject,
    required this.grade,
    required this.topic,
    required this.summary,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subject': subject,
    'grade': grade,
    'topic': topic,
    'summary': summary,
  };

  factory McpLessonSummary.fromMap(Map<String, dynamic> map) {
    return McpLessonSummary(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      grade: (map['grade'] as num?)?.toInt() ?? 7,
      topic: map['topic'] as String? ?? '',
      summary: map['summary'] as String? ?? '',
    );
  }
}

/// Detailed lesson plan returned from get_lesson (F15-06).
class McpLessonDetail {
  final String id;
  final String title;
  final String subject;
  final int grade;
  final String topic;
  final String summary;
  final String content;
  final String author;

  const McpLessonDetail({
    required this.id,
    required this.title,
    required this.subject,
    required this.grade,
    required this.topic,
    required this.summary,
    required this.content,
    required this.author,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subject': subject,
    'grade': grade,
    'topic': topic,
    'summary': summary,
    'content': content,
    'author': author,
  };

  factory McpLessonDetail.fromMap(Map<String, dynamic> map) {
    return McpLessonDetail(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      grade: (map['grade'] as num?)?.toInt() ?? 7,
      topic: map['topic'] as String? ?? '',
      summary: map['summary'] as String? ?? '',
      content: map['content'] as String? ?? '',
      author: map['author'] as String? ?? 'Методический отдел CraftAI',
    );
  }
}

/// Sanitized educational log record of JSON-RPC 2.0 communication (F15-07).
class McpRpcLog {
  final DateTime timestamp;
  final String method;
  final String requestJson;
  final String responseJson;
  final int durationMs;
  final bool isError;

  const McpRpcLog({
    required this.timestamp,
    required this.method,
    required this.requestJson,
    required this.responseJson,
    required this.durationMs,
    this.isError = false,
  });
}
