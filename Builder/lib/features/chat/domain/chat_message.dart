enum MessageRole {
  user,
  assistant,
  system;

  static MessageRole fromString(String value) {
    switch (value.toLowerCase()) {
      case 'user':
        return MessageRole.user;
      case 'assistant':
        return MessageRole.assistant;
      case 'system':
      default:
        return MessageRole.system;
    }
  }

  String toDbValue() => name;
}

enum MessageStatus {
  pending,
  streaming,
  completed,
  interrupted,
  error;

  static MessageStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'pending':
        return MessageStatus.pending;
      case 'streaming':
        return MessageStatus.streaming;
      case 'completed':
        return MessageStatus.completed;
      case 'interrupted':
        return MessageStatus.interrupted;
      case 'error':
        return MessageStatus.error;
      default:
        return MessageStatus.completed;
    }
  }

  String toDbValue() => name;
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String ownerId;
  final MessageRole role;
  final String content;
  final MessageStatus status;
  final String? requestId;
  final int? assistantVersion;
  final String? category;
  final String? modelId;
  final DateTime createdAtUtc;
  final String? errorMessage;
  final bool isReported;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.ownerId,
    required this.role,
    required this.content,
    required this.status,
    this.requestId,
    this.assistantVersion,
    this.category,
    this.modelId,
    required this.createdAtUtc,
    this.errorMessage,
    this.isReported = false,
  });

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get isSystem => role == MessageRole.system;

  ChatMessage copyWith({
    String? content,
    MessageStatus? status,
    String? requestId,
    int? assistantVersion,
    String? category,
    String? modelId,
    String? errorMessage,
    bool? isReported,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      ownerId: ownerId,
      role: role,
      content: content ?? this.content,
      status: status ?? this.status,
      requestId: requestId ?? this.requestId,
      assistantVersion: assistantVersion ?? this.assistantVersion,
      category: category ?? this.category,
      modelId: modelId ?? this.modelId,
      createdAtUtc: createdAtUtc,
      errorMessage: errorMessage ?? this.errorMessage,
      isReported: isReported ?? this.isReported,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'owner_id': ownerId,
      'role': role.toDbValue(),
      'content': content,
      'status': status.toDbValue(),
      'request_id': requestId,
      'assistant_version': assistantVersion,
      'created_at_utc': createdAtUtc.toIso8601String(),
    };
  }

  factory ChatMessage.fromMap(
    Map<String, dynamic> map, {
    String? category,
    String? modelId,
    String? errorMessage,
    bool isReported = false,
  }) {
    return ChatMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      ownerId: map['owner_id'] as String,
      role: MessageRole.fromString(map['role'] as String),
      content: map['content'] as String,
      status: MessageStatus.fromString(map['status'] as String),
      requestId: map['request_id'] as String?,
      assistantVersion: map['assistant_version'] as int?,
      category: category,
      modelId: modelId,
      createdAtUtc: DateTime.parse(map['created_at_utc'] as String),
      errorMessage: errorMessage,
      isReported: isReported,
    );
  }
}
