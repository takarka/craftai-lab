import 'tool_definition.dart';

/// Registry of all standard tools available to the assistant (F14-01).
class ToolsRegistry {
  static const String createNote = 'create_note';
  static const String readNotes = 'read_notes';
  static const String deleteNote = 'delete_note';

  static final List<ToolDefinition> allTools = [
    // Notes
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
