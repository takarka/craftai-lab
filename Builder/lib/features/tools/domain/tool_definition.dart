/// Category of the tool (F14-02).
enum ToolCategory {
  calendar('calendar', 'Календарь и расписание'),
  notes('notes', 'Личные заметки и черновики'),
  communication('communication', 'Связь и звонки'),
  search('search', 'Поиск в интернете');

  final String id;
  final String label;

  const ToolCategory(this.id, this.label);
}

/// Execution capability requirement for a tool (F14-01, F14-05).
enum ToolCapability {
  /// Read-only inspection; does not alter state. Executed directly if granted.
  readOnly('read_only'),

  /// Mutating or external action; requires explicit teacher confirmation (D07/State Machine) before execution.
  requiresConfirmation('requires_confirmation');

  final String id;
  const ToolCapability(this.id);
}

/// OS Permission requirement status.
enum OsPermissionStatus {
  notRequired('not_required', 'Не требуется'),
  granted('granted', 'Разрешено в системе'),
  denied('denied', 'Запрещено в системе'),
  notRequested('not_requested', 'Запрос при первом вызове');

  final String id;
  final String label;
  const OsPermissionStatus(this.id, this.label);
}

/// Definition of a tool available in the assistant tool registry (F14-01).
class ToolDefinition {
  final String name;
  final String displayName;
  final String description;
  final ToolCategory category;
  final ToolCapability capability;
  final OsPermissionStatus defaultOsPermission;
  final Map<String, dynamic> parametersSchema;

  const ToolDefinition({
    required this.name,
    required this.displayName,
    required this.description,
    required this.category,
    required this.capability,
    this.defaultOsPermission = OsPermissionStatus.notRequired,
    required this.parametersSchema,
  });

  bool get requiresConfirmation => capability == ToolCapability.requiresConfirmation;

  /// Returns wire-format schema for LLM function calling / tools array.
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

  /// Validates incoming arguments against required keys, types and formats.
  List<String> validateArguments(Map<String, dynamic> args) {
    final errors = <String>[];
    final requiredProps = parametersSchema['required'] as List<dynamic>?;
    if (requiredProps != null) {
      for (final prop in requiredProps) {
        if (!args.containsKey(prop) || args[prop] == null) {
          errors.add('Отсутствует обязательный параметр: $prop');
        }
      }
    }

    final properties = parametersSchema['properties'] as Map<String, dynamic>? ?? {};
    for (final entry in args.entries) {
      final propName = entry.key;
      final propVal = entry.value;
      final propSchema = properties[propName] as Map<String, dynamic>?;
      if (propSchema != null && propVal != null) {
        final expectedType = propSchema['type'] as String?;
        if (expectedType == 'string' && propVal is! String) {
          errors.add('Параметр $propName должен быть строкой');
        } else if (expectedType == 'boolean' && propVal is! bool) {
          errors.add('Параметр $propName должен быть логическим значением');
        } else if (expectedType == 'number' && propVal is! num) {
          errors.add('Параметр $propName должен быть числом');
        } else if (expectedType == 'integer' && propVal is! int) {
          errors.add('Параметр $propName должен быть целым числом');
        }

        if (expectedType == 'string' && (propName.endsWith('_time') || propName.endsWith('_date'))) {
          if (propVal is String && DateTime.tryParse(propVal) == null) {
            errors.add('Параметр $propName должен содержать корректную дату/время ISO-8601');
          }
        }
      }
    }
    return errors;
  }
}
