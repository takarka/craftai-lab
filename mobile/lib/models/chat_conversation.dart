import 'chat_message.dart';

class ChatConversation {
  final String id;
  final DateTime updatedAt;
  final List<ChatMessage> messages;
  final String summary;
  final String? summarizedThroughId;

  ChatConversation({
    required this.id,
    required this.updatedAt,
    List<ChatMessage> messages = const [],
    this.summary = '',
    this.summarizedThroughId,
  }) : messages = List.unmodifiable(messages);

  String get title {
    final first = messages.where((m) => m.isUser).firstOrNull;
    if (first == null) return 'Новый чат';
    final value = first.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.runes.length <= 48
        ? value
        : '${String.fromCharCodes(value.runes.take(48))}…';
  }

  ChatConversation withMessages(
    List<ChatMessage> value, {
    bool clearSummary = false,
  }) => ChatConversation(
    id: id,
    updatedAt: DateTime.now(),
    messages: value,
    summary: clearSummary ? '' : summary,
    summarizedThroughId: clearSummary ? null : summarizedThroughId,
  );

  ChatConversation withSummary(String value, String throughId) =>
      ChatConversation(
        id: id,
        updatedAt: DateTime.now(),
        messages: messages,
        summary: value,
        summarizedThroughId: throughId,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
    'summary': summary,
    'summarizedThroughId': summarizedThroughId,
  };

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final messages = (json['messages'] as List)
        .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();
    final throughId = json['summarizedThroughId'] as String?;
    if (throughId != null &&
        !messages.any((m) => m.id == throughId && !m.isUser)) {
      throw const FormatException('Invalid summary boundary');
    }
    return ChatConversation(
      id: json['id'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      messages: messages,
      summary: json['summary'] as String? ?? '',
      summarizedThroughId: throughId,
    );
  }
}

class ChatArchive {
  final List<ChatConversation> conversations;
  final String activeId;
  final int contextSize;

  ChatArchive({
    required List<ChatConversation> conversations,
    required this.activeId,
    this.contextSize = 2048,
  }) : conversations = List.unmodifiable(conversations);

  Map<String, dynamic> toJson() => {
    'version': 1,
    'activeId': activeId,
    'contextSize': contextSize,
    'conversations': conversations.map((c) => c.toJson()).toList(),
  };

  factory ChatArchive.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported archive version');
    }
    final chats = (json['conversations'] as List)
        .map(
          (c) => ChatConversation.fromJson(Map<String, dynamic>.from(c as Map)),
        )
        .toList();
    final activeId = json['activeId'] as String;
    if (chats.isEmpty ||
        !chats.any((c) => c.id == activeId) ||
        chats.map((c) => c.id).toSet().length != chats.length) {
      throw const FormatException('Invalid chat archive');
    }
    final size = json['contextSize'] as int? ?? 2048;
    if (![1024, 2048, 4096, 8192].contains(size)) {
      throw const FormatException('Invalid context size');
    }
    return ChatArchive(
      conversations: chats,
      activeId: activeId,
      contextSize: size,
    );
  }
}
