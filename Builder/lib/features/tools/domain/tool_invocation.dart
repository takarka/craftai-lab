import 'dart:convert';

/// Record of a tool execution logged in SQLite (tableToolInvocations) (F14-11).
class ToolInvocationRecord {
  final String id;
  final String ownerId;
  final String toolName;
  final String invocationSource;
  final Map<String, dynamic> args;
  final Map<String, dynamic>? result;
  final DateTime startedAtUtc;
  final DateTime? completedAtUtc;
  final String? executionId;

  const ToolInvocationRecord({
    required this.id,
    required this.ownerId,
    required this.toolName,
    this.invocationSource = 'assistant_chat',
    required this.args,
    this.result,
    required this.startedAtUtc,
    this.completedAtUtc,
    this.executionId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'tool_name': toolName,
      'invocation_source': invocationSource,
      'args_json': jsonEncode(args),
      'result_json': result != null ? jsonEncode(result) : null,
      'started_at_utc': startedAtUtc.toIso8601String(),
      'completed_at_utc': completedAtUtc?.toIso8601String(),
      'execution_id': executionId,
    };
  }

  factory ToolInvocationRecord.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> parsedArgs = {};
    try {
      final rawArgs = map['args_json'];
      if (rawArgs is String) {
        parsedArgs = jsonDecode(rawArgs) as Map<String, dynamic>;
      } else if (rawArgs is Map) {
        parsedArgs = Map<String, dynamic>.from(rawArgs);
      }
    } catch (_) {}

    Map<String, dynamic>? parsedResult;
    try {
      final rawRes = map['result_json'];
      if (rawRes is String) {
        parsedResult = jsonDecode(rawRes) as Map<String, dynamic>;
      } else if (rawRes is Map) {
        parsedResult = Map<String, dynamic>.from(rawRes);
      }
    } catch (_) {}

    return ToolInvocationRecord(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      toolName: map['tool_name'] as String,
      invocationSource: map['invocation_source'] as String? ?? 'assistant_chat',
      args: parsedArgs,
      result: parsedResult,
      startedAtUtc:
          DateTime.tryParse(map['started_at_utc'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      completedAtUtc: DateTime.tryParse(
        map['completed_at_utc'] as String? ?? '',
      )?.toUtc(),
      executionId: map['execution_id'] as String?,
    );
  }
}
