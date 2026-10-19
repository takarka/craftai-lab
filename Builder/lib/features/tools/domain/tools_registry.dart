import 'tool_definition.dart';

/// Registry of all standard tools available to the assistant (F14-01).
class ToolsRegistry {
  static const String readCalendar = 'read_calendar';
  static const String createCalendarEvent = 'create_calendar_event';
  static const String createNote = 'create_note';
  static const String readNotes = 'read_notes';
  static const String deleteNote = 'delete_note';
  // Retained only to identify historical records; excluded from this release.
  static const String prepareCall = 'prepare_call';
  static const String webSearch = 'web_search';

  static final List<ToolDefinition> allTools = [
    // 1. Calendar
    const ToolDefinition(
      name: readCalendar,
      displayName: 'Чтение календаря',
      description:
          'Просмотреть события и расписание уроков за указанный период времени.',
      category: ToolCategory.calendar,
      capability: ToolCapability.readOnly,
      defaultOsPermission: OsPermissionStatus.notRequested,
      parametersSchema: {
        'type': 'object',
        'properties': {
          'start_date': {
            'type': 'string',
            'description':
                'Начало периода (ISO-8601, например 2026-10-20T08:00:00Z)',
          },
          'end_date': {
            'type': 'string',
            'description':
                'Конец периода (ISO-8601, например 2026-10-20T18:00:00Z)',
          },
        },
        'required': ['start_date', 'end_date'],
      },
    ),
    const ToolDefinition(
      name: createCalendarEvent,
      displayName: 'Создание события',
      description:
          'Создать новое событие, урок или консультацию в календаре (требует подтверждения учителя).',
      category: ToolCategory.calendar,
      capability: ToolCapability.requiresConfirmation,
      defaultOsPermission: OsPermissionStatus.notRequested,
      parametersSchema: {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description':
                'Название события или урока (например: «Консультация по алгебре 7Б»)',
          },
          'start_time': {
            'type': 'string',
            'description': 'Время начала (ISO-8601)',
          },
          'end_time': {
            'type': 'string',
            'description': 'Время окончания (ISO-8601)',
          },
          'is_all_day': {'type': 'boolean', 'description': 'Весь день'},
          'location': {
            'type': 'string',
            'description': 'Кабинет или место проведения',
          },
          'notes': {
            'type': 'string',
            'description': 'Дополнительные заметки к событию',
          },
        },
        'required': ['title', 'start_time', 'end_time'],
      },
    ),

    // 2. Notes
    const ToolDefinition(
      name: createNote,
      displayName: 'Создать заметку',
      description:
          'Сохранить учебный конспект, план урока или черновик в приватных заметках на устройстве.',
      category: ToolCategory.notes,
      capability: ToolCapability.requiresConfirmation,
      defaultOsPermission: OsPermissionStatus.notRequired,
      parametersSchema: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'Заголовок заметки'},
          'content': {'type': 'string', 'description': 'Содержимое заметки'},
        },
        'required': ['title', 'content'],
      },
    ),
    const ToolDefinition(
      name: readNotes,
      displayName: 'Поиск заметок',
      description:
          'Найти и прочитать сохранённые заметки и черновики ассистента.',
      category: ToolCategory.notes,
      capability: ToolCapability.readOnly,
      defaultOsPermission: OsPermissionStatus.notRequired,
      parametersSchema: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'Поисковый запрос по заголовку или содержимому заметок',
          },
        },
      },
    ),
    const ToolDefinition(
      name: deleteNote,
      displayName: 'Удалить заметку',
      description:
          'Удалить сохранённую заметку (требует подтверждения учителя).',
      category: ToolCategory.notes,
      capability: ToolCapability.requiresConfirmation,
      defaultOsPermission: OsPermissionStatus.notRequired,
      parametersSchema: {
        'type': 'object',
        'properties': {
          'note_id': {
            'type': 'string',
            'description': 'Идентификатор заметки для удаления',
          },
        },
        'required': ['note_id'],
      },
    ),

    // 3. Search
    const ToolDefinition(
      name: webSearch,
      displayName: 'Поиск в интернете',
      description:
          'Найти актуальные образовательные статьи или материалы в интернете через CraftAI Search (по умолчанию выключен).',
      category: ToolCategory.search,
      capability: ToolCapability.readOnly,
      defaultOsPermission: OsPermissionStatus.notRequired,
      parametersSchema: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Поисковый запрос в интернет',
          },
        },
        'required': ['query'],
      },
    ),
  ];

  static ToolDefinition? getByName(String name) {
    for (final tool in allTools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  static List<ToolDefinition> getByCategory(ToolCategory category) {
    return allTools.where((t) => t.category == category).toList();
  }
}
