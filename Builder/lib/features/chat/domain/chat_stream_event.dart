sealed class StreamEvent {
  final String type;
  final String requestId;
  final int sequence;
  final String eventId;

  const StreamEvent({
    required this.type,
    required this.requestId,
    required this.sequence,
    required this.eventId,
  });

  static StreamEvent fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final reqId = json['requestId'] as String? ?? '';
    final seq = (json['sequence'] as num?)?.toInt() ?? 0;
    final evtId = json['eventId'] as String? ?? '';

    switch (type) {
      case 'start':
        return StartStreamEvent(
          requestId: reqId,
          sequence: seq,
          eventId: evtId,
          modelId: json['modelId'] as String? ?? '',
        );
      case 'text_delta':
        return TextDeltaStreamEvent(
          requestId: reqId,
          sequence: seq,
          eventId: evtId,
          text: json['text'] as String? ?? '',
        );
      case 'tool_call_start':
        return ToolCallStartStreamEvent(
          requestId: reqId,
          sequence: seq,
          eventId: evtId,
          toolCallId: json['toolCallId'] as String? ?? '',
          name: json['name'] as String? ?? '',
        );
      case 'tool_call_delta':
        return ToolCallDeltaStreamEvent(
          requestId: reqId,
          sequence: seq,
          eventId: evtId,
          toolCallId: json['toolCallId'] as String? ?? '',
          argumentsDelta: json['argumentsDelta'] as String? ?? '',
        );
      case 'tool_call_end':
        return ToolCallEndStreamEvent(
          requestId: reqId,
          sequence: seq,
          eventId: evtId,
          toolCallId: json['toolCallId'] as String? ?? '',
          arguments: json['arguments'],
        );
      case 'usage':
        final tokens = json['tokens'] as Map<String, dynamic>? ?? {};
        return UsageStreamEvent(
          requestId: reqId,
          sequence: seq,
          eventId: evtId,
          inputTokens: (tokens['inputTokens'] as num?)?.toInt() ?? 0,
          outputTokens: (tokens['outputTokens'] as num?)?.toInt() ?? 0,
          totalTokens: (tokens['totalTokens'] as num?)?.toInt() ?? 0,
          partial: json['partial'] as bool? ?? false,
        );
      case 'terminal':
        return TerminalStreamEvent(
          requestId: reqId,
          sequence: seq,
          eventId: evtId,
          state: json['state'] as String? ?? 'completed',
          code: json['code'] as String?,
          finishReason: json['finishReason'] as String?,
          continuation: json['continuation'] as Map<String, dynamic>?,
        );
      default:
        return UnknownStreamEvent(
          type: type,
          requestId: reqId,
          sequence: seq,
          eventId: evtId,
          payload: json,
        );
    }
  }
}

class StartStreamEvent extends StreamEvent {
  final String modelId;

  const StartStreamEvent({
    required super.requestId,
    required super.sequence,
    required super.eventId,
    required this.modelId,
  }) : super(type: 'start');
}

class TextDeltaStreamEvent extends StreamEvent {
  final String text;

  const TextDeltaStreamEvent({
    required super.requestId,
    required super.sequence,
    required super.eventId,
    required this.text,
  }) : super(type: 'text_delta');
}

class ToolCallStartStreamEvent extends StreamEvent {
  final String toolCallId;
  final String name;

  const ToolCallStartStreamEvent({
    required super.requestId,
    required super.sequence,
    required super.eventId,
    required this.toolCallId,
    required this.name,
  }) : super(type: 'tool_call_start');
}

class ToolCallDeltaStreamEvent extends StreamEvent {
  final String toolCallId;
  final String argumentsDelta;

  const ToolCallDeltaStreamEvent({
    required super.requestId,
    required super.sequence,
    required super.eventId,
    required this.toolCallId,
    required this.argumentsDelta,
  }) : super(type: 'tool_call_delta');
}

class ToolCallEndStreamEvent extends StreamEvent {
  final String toolCallId;
  final dynamic arguments;

  const ToolCallEndStreamEvent({
    required super.requestId,
    required super.sequence,
    required super.eventId,
    required this.toolCallId,
    this.arguments,
  }) : super(type: 'tool_call_end');
}

class UsageStreamEvent extends StreamEvent {
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final bool partial;

  const UsageStreamEvent({
    required super.requestId,
    required super.sequence,
    required super.eventId,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.partial,
  }) : super(type: 'usage');
}

class TerminalStreamEvent extends StreamEvent {
  final String state;
  final String? code;
  final String? finishReason;
  final Map<String, dynamic>? continuation;

  const TerminalStreamEvent({
    required super.requestId,
    required super.sequence,
    required super.eventId,
    required this.state,
    this.code,
    this.finishReason,
    this.continuation,
  }) : super(type: 'terminal');

  bool get isCompleted => state == 'completed';
  bool get isInterrupted => state == 'interrupted';
  bool get isError => state == 'error';
}

class UnknownStreamEvent extends StreamEvent {
  final Map<String, dynamic> payload;

  const UnknownStreamEvent({
    required super.type,
    required super.requestId,
    required super.sequence,
    required super.eventId,
    required this.payload,
  });
}
