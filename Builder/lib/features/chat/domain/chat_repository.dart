import 'chat_message.dart';
import 'context_assembler.dart';
import 'conversation.dart';

abstract class ChatRepository {
  Future<Conversation> createConversation({
    required String ownerId,
    String? title,
    RetentionPolicy retentionPolicy = RetentionPolicy.persistent,
  });

  Future<List<Conversation>> getConversations({required String ownerId});

  Future<Conversation?> getConversation({required String id});

  Future<void> updateConversationTitle({
    required String id,
    required String title,
  });

  Future<void> deleteConversation({required String id});

  Future<List<ChatMessage>> getMessages({required String conversationId});

  Future<void> saveMessage(ChatMessage message);

  Future<void> updateMessage(ChatMessage message);

  Future<void> deleteMessage({required String id});

  Future<void> reportMessage({
    required String requestId,
    required String reason,
    String? comment,
  });

  Future<bool> isMessageReported({required String requestId});

  Future<void> saveContextManifest(ContextManifest manifest);

  Future<ContextManifest?> getContextManifest({required String requestId});
}
