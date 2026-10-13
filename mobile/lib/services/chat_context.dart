import 'package:llamadart/llamadart.dart';

import '../models/chat_message.dart';

class ChatTurn {
  final ChatMessage user;
  final ChatMessage assistant;
  const ChatTurn(this.user, this.assistant);
  List<LlamaChatMessage> get modelMessages => [
    LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: user.contextText ?? user.text,
    ),
    LlamaChatMessage.fromText(
      role: LlamaChatRole.assistant,
      text: assistant.text,
    ),
  ];
}

List<ChatTurn> completedChatTurns(
  List<ChatMessage> messages, {
  String? afterId,
}) {
  final boundary = afterId == null
      ? -1
      : messages.indexWhere((m) => m.id == afterId);
  final turns = <ChatTurn>[];
  for (var i = boundary + 1; i + 1 < messages.length; i++) {
    final user = messages[i];
    final assistant = messages[i + 1];
    if (!user.isUser ||
        assistant.isUser ||
        assistant.isGenerating ||
        assistant.text.trim().isEmpty) {
      continue;
    }
    turns.add(ChatTurn(user, assistant));
    i++;
  }
  return turns;
}

/// Reasoning and error notices are excluded from later turns.
List<LlamaChatMessage> buildChatContext(
  List<ChatMessage> messages, {
  String? afterId,
}) => completedChatTurns(
  messages,
  afterId: afterId,
).expand((turn) => turn.modelMessages).toList();

String contextSystemPrompt(String systemPrompt, String summary) =>
    summary.isEmpty
    ? systemPrompt
    : '$systemPrompt\n\nКраткое содержание предыдущей части этого диалога (используй как справочную информацию):\n$summary';

ChatSession createChatSession(
  LlamaEngine engine,
  List<ChatMessage> messages, {
  required String systemPrompt,
  String summary = '',
  String? summarizedThroughId,
}) {
  final session = ChatSession(
    engine,
    systemPrompt: contextSystemPrompt(systemPrompt, summary),
  );
  for (final message in buildChatContext(
    messages,
    afterId: summarizedThroughId,
  )) {
    session.addMessage(message);
  }
  return session;
}
