import 'package:sqflite/sqflite.dart';
import '../../../../core/storage/database/storage_database.dart';
import '../../../../core/storage/schema/storage_schema_v1.dart';
import '../domain/chat_message.dart';
import '../domain/chat_repository.dart';
import '../domain/context_assembler.dart';
import '../domain/conversation.dart';

class PersistentChatRepository implements ChatRepository {
  final StorageDatabase database;

  // In-memory storage for ephemeral conversations and reported request IDs
  final Map<String, Conversation> _ephemeralConversations = {};
  final Map<String, List<ChatMessage>> _ephemeralMessages = {};
  final Set<String> _reportedRequestIds = {};
  final Map<String, ContextManifest> _manifests = {};

  PersistentChatRepository({required this.database});

  Future<Database> get _db async {
    if (!database.isOpen) {
      await database.open();
    }
    return database.db;
  }

  int _counter = 0;

  @override
  Future<Conversation> createConversation({
    required String ownerId,
    String? title,
    RetentionPolicy retentionPolicy = RetentionPolicy.persistent,
  }) async {
    final now = DateTime.now().toUtc();
    final conversation = Conversation(
      id: 'conv_${now.millisecondsSinceEpoch}_${now.microsecond}_${++_counter}',
      ownerId: ownerId,
      title: title ?? (retentionPolicy == RetentionPolicy.ephemeral ? 'Временный разговор' : 'Новый разговор'),
      createdAtUtc: now,
      activityAtUtc: now,
      retentionPolicy: retentionPolicy,
    );

    if (retentionPolicy == RetentionPolicy.ephemeral) {
      _ephemeralConversations[conversation.id] = conversation;
      _ephemeralMessages[conversation.id] = [];
      return conversation;
    }

    final db = await _db;
    await db.insert(
      StorageSchemaV1.tableConversations,
      conversation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return conversation;
  }

  @override
  Future<List<Conversation>> getConversations({required String ownerId}) async {
    final db = await _db;
    final rows = await db.query(
      StorageSchemaV1.tableConversations,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'activity_at_utc DESC',
    );

    final persistent = rows.map((r) => Conversation.fromMap(r)).toList();
    final ephemeral = _ephemeralConversations.values
        .where((c) => c.ownerId == ownerId)
        .toList()
      ..sort((a, b) => b.activityAtUtc.compareTo(a.activityAtUtc));

    return [...ephemeral, ...persistent];
  }

  @override
  Future<Conversation?> getConversation({required String id}) async {
    if (_ephemeralConversations.containsKey(id)) {
      return _ephemeralConversations[id];
    }

    final db = await _db;
    final rows = await db.query(
      StorageSchemaV1.tableConversations,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return Conversation.fromMap(rows.first);
  }

  @override
  Future<void> updateConversationTitle({
    required String id,
    required String title,
  }) async {
    if (_ephemeralConversations.containsKey(id)) {
      final existing = _ephemeralConversations[id]!;
      _ephemeralConversations[id] = existing.copyWith(
        title: title,
        activityAtUtc: DateTime.now().toUtc(),
      );
      return;
    }

    final db = await _db;
    await db.update(
      StorageSchemaV1.tableConversations,
      {
        'title': title,
        'activity_at_utc': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteConversation({required String id}) async {
    if (_ephemeralConversations.containsKey(id)) {
      _ephemeralConversations.remove(id);
      _ephemeralMessages.remove(id);
      return;
    }

    final db = await _db;
    await db.delete(
      StorageSchemaV1.tableMessages,
      where: 'conversation_id = ?',
      whereArgs: [id],
    );
    await db.delete(
      StorageSchemaV1.tableConversations,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<ChatMessage>> getMessages({required String conversationId}) async {
    if (_ephemeralConversations.containsKey(conversationId)) {
      final msgs = _ephemeralMessages[conversationId] ?? [];
      return msgs.map((m) {
        final reported = m.requestId != null && _reportedRequestIds.contains(m.requestId);
        return m.copyWith(isReported: reported);
      }).toList();
    }

    final db = await _db;
    final rows = await db.query(
      StorageSchemaV1.tableMessages,
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at_utc ASC',
    );

    return rows.map((r) {
      final msg = ChatMessage.fromMap(r);
      final reported = msg.requestId != null && _reportedRequestIds.contains(msg.requestId);
      return msg.copyWith(isReported: reported);
    }).toList();
  }

  @override
  Future<void> saveMessage(ChatMessage message) async {
    if (_ephemeralConversations.containsKey(message.conversationId)) {
      _ephemeralMessages.putIfAbsent(message.conversationId, () => []);
      _ephemeralMessages[message.conversationId]!.add(message);
      final conv = _ephemeralConversations[message.conversationId];
      if (conv != null) {
        _ephemeralConversations[message.conversationId] = conv.copyWith(
          activityAtUtc: message.createdAtUtc,
        );
      }
      return;
    }

    final db = await _db;
    await db.insert(
      StorageSchemaV1.tableMessages,
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.update(
      StorageSchemaV1.tableConversations,
      {'activity_at_utc': message.createdAtUtc.toIso8601String()},
      where: 'id = ?',
      whereArgs: [message.conversationId],
    );
  }

  @override
  Future<void> updateMessage(ChatMessage message) async {
    if (_ephemeralConversations.containsKey(message.conversationId)) {
      final list = _ephemeralMessages[message.conversationId];
      if (list != null) {
        final idx = list.indexWhere((m) => m.id == message.id);
        if (idx != -1) {
          list[idx] = message;
        } else {
          list.add(message);
        }
      }
      return;
    }

    final db = await _db;
    await db.update(
      StorageSchemaV1.tableMessages,
      message.toMap(),
      where: 'id = ?',
      whereArgs: [message.id],
    );
  }

  @override
  Future<void> deleteMessage({required String id}) async {
    for (final list in _ephemeralMessages.values) {
      list.removeWhere((m) => m.id == id);
    }

    final db = await _db;
    await db.delete(
      StorageSchemaV1.tableMessages,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> reportMessage({
    required String requestId,
    required String reason,
    String? comment,
  }) async {
    _reportedRequestIds.add(requestId);
  }

  @override
  Future<bool> isMessageReported({required String requestId}) async {
    return _reportedRequestIds.contains(requestId);
  }

  @override
  Future<void> saveContextManifest(ContextManifest manifest) async {
    _manifests[manifest.requestId] = manifest;
  }

  @override
  Future<ContextManifest?> getContextManifest({required String requestId}) async {
    return _manifests[requestId];
  }
}

class InMemoryChatRepository implements ChatRepository {
  final Map<String, Conversation> _conversations = {};
  final Map<String, List<ChatMessage>> _messages = {};
  final Set<String> _reportedRequestIds = {};
  final Map<String, ContextManifest> _manifests = {};
  int _counter = 0;

  @override
  Future<Conversation> createConversation({
    required String ownerId,
    String? title,
    RetentionPolicy retentionPolicy = RetentionPolicy.persistent,
  }) async {
    final now = DateTime.now().toUtc();
    final conv = Conversation(
      id: 'mock_conv_${now.microsecondsSinceEpoch}_${++_counter}',
      ownerId: ownerId,
      title: title ?? 'Тестовый разговор',
      createdAtUtc: now,
      activityAtUtc: now,
      retentionPolicy: retentionPolicy,
    );
    _conversations[conv.id] = conv;
    _messages[conv.id] = [];
    return conv;
  }

  @override
  Future<List<Conversation>> getConversations({required String ownerId}) async {
    final list = _conversations.values.where((c) => c.ownerId == ownerId).toList();
    list.sort((a, b) => b.activityAtUtc.compareTo(a.activityAtUtc));
    return list;
  }

  @override
  Future<Conversation?> getConversation({required String id}) async {
    return _conversations[id];
  }

  @override
  Future<void> updateConversationTitle({
    required String id,
    required String title,
  }) async {
    final existing = _conversations[id];
    if (existing != null) {
      _conversations[id] = existing.copyWith(
        title: title,
        activityAtUtc: DateTime.now().toUtc(),
      );
    }
  }

  @override
  Future<void> deleteConversation({required String id}) async {
    _conversations.remove(id);
    _messages.remove(id);
  }

  @override
  Future<List<ChatMessage>> getMessages({required String conversationId}) async {
    return (_messages[conversationId] ?? []).map((m) {
      final reported = m.requestId != null && _reportedRequestIds.contains(m.requestId);
      return m.copyWith(isReported: reported);
    }).toList();
  }

  @override
  Future<void> saveMessage(ChatMessage message) async {
    _messages.putIfAbsent(message.conversationId, () => []);
    _messages[message.conversationId]!.add(message);
    final conv = _conversations[message.conversationId];
    if (conv != null) {
      _conversations[message.conversationId] = conv.copyWith(
        activityAtUtc: message.createdAtUtc,
      );
    }
  }

  @override
  Future<void> updateMessage(ChatMessage message) async {
    final list = _messages[message.conversationId];
    if (list != null) {
      final idx = list.indexWhere((m) => m.id == message.id);
      if (idx != -1) {
        list[idx] = message;
      } else {
        list.add(message);
      }
    }
  }

  @override
  Future<void> deleteMessage({required String id}) async {
    for (final list in _messages.values) {
      list.removeWhere((m) => m.id == id);
    }
  }

  @override
  Future<void> reportMessage({
    required String requestId,
    required String reason,
    String? comment,
  }) async {
    _reportedRequestIds.add(requestId);
  }

  @override
  Future<bool> isMessageReported({required String requestId}) async {
    return _reportedRequestIds.contains(requestId);
  }

  @override
  Future<void> saveContextManifest(ContextManifest manifest) async {
    _manifests[manifest.requestId] = manifest;
  }

  @override
  Future<ContextManifest?> getContextManifest({required String requestId}) async {
    return _manifests[requestId];
  }
}
