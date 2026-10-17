import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/storage_providers.dart';
import '../models/infrastructure/craft_ai_client.dart';
import '../models/model_providers.dart';
import '../session/session_providers.dart';
import 'domain/chat_message.dart';
import 'domain/chat_repository.dart';
import 'domain/chat_stream_event.dart';
import 'domain/context_assembler.dart';
import 'domain/conversation.dart';
import 'infrastructure/chat_stream_client.dart';
import 'infrastructure/persistent_chat_repository.dart';
import '../trace/domain/request_trace.dart';
import '../trace/trace_providers.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final db = ref.watch(storageDatabaseProvider);
  if (db == null) return InMemoryChatRepository();
  return PersistentChatRepository(database: db);
});

final chatStreamClientProvider = Provider<ChatStreamClient>((ref) {
  final tokens = ref.watch(secureTokenStorageProvider);
  return ChatStreamClient(tokenStorage: tokens);
});

class ConversationsNotifier extends Notifier<List<Conversation>> {
  ConversationsNotifier(this.ownerId);
  final String ownerId;

  @override
  List<Conversation> build() {
    final repo = ref.watch(chatRepositoryProvider);
    repo.getConversations(ownerId: ownerId).then((list) {
      if (ref.mounted) {
        state = list;
      }
    });
    return const [];
  }

  Future<void> _load() async {
    if (!ref.mounted) return;
    final repo = ref.read(chatRepositoryProvider);
    final list = await repo.getConversations(ownerId: ownerId);
    if (!ref.mounted) return;
    state = list;
  }

  Future<Conversation> createNew({RetentionPolicy retentionPolicy = RetentionPolicy.persistent, String? title}) async {
    final repo = ref.read(chatRepositoryProvider);
    final conv = await repo.createConversation(
      ownerId: ownerId,
      retentionPolicy: retentionPolicy,
      title: title,
    );
    if (ref.mounted) {
      await _load();
    }
    return conv;
  }

  Future<void> delete(String id) async {
    final repo = ref.read(chatRepositoryProvider);
    await repo.deleteConversation(id: id);
    if (ref.mounted) {
      await _load();
    }
  }

  Future<void> refresh() async {
    if (ref.mounted) {
      await _load();
    }
  }
}

final conversationsProvider = NotifierProvider.family<ConversationsNotifier, List<Conversation>, String>(
  ConversationsNotifier.new,
);

class ChatState {
  final Conversation? activeConversation;
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isGenerating;
  final bool isSlowResponse;
  final String? error;
  final String? activeModelId;

  const ChatState({
    this.activeConversation,
    this.messages = const [],
    this.isLoading = false,
    this.isGenerating = false,
    this.isSlowResponse = false,
    this.error,
    this.activeModelId,
  });

  ChatState copyWith({
    Conversation? activeConversation,
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isGenerating,
    bool? isSlowResponse,
    String? error,
    bool clearError = false,
    String? activeModelId,
  }) {
    return ChatState(
      activeConversation: activeConversation ?? this.activeConversation,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isGenerating: isGenerating ?? this.isGenerating,
      isSlowResponse: isSlowResponse ?? this.isSlowResponse,
      error: clearError ? null : (error ?? this.error),
      activeModelId: activeModelId ?? this.activeModelId,
    );
  }
}

class ChatSessionNotifier extends Notifier<ChatState> {
  ChatSessionNotifier(this.ownerId);
  final String ownerId;

  ChatCancellationToken? _currentCancellationToken;
  Timer? _slowTimer;
  Timer? _coalescingTimer;
  String _bufferedText = '';

  @override
  ChatState build() {
    ref.onDispose(() {
      _currentCancellationToken?.cancel();
      _slowTimer?.cancel();
      _coalescingTimer?.cancel();
    });

    // Auto-initialize first conversation if none
    Future.microtask(() => _initialize());

    return const ChatState(isLoading: true);
  }

  Future<void> _initialize() async {
    if (!ref.mounted) return;
    final repo = ref.read(chatRepositoryProvider);
    final convs = await repo.getConversations(ownerId: ownerId);
    if (!ref.mounted) return;
    if (convs.isNotEmpty) {
      await switchConversation(convs.first.id);
    } else {
      await startNewConversation();
    }
  }

  Future<void> switchConversation(String conversationId) async {
    _currentCancellationToken?.cancel();
    _slowTimer?.cancel();
    _coalescingTimer?.cancel();

    if (!ref.mounted) return;
    state = state.copyWith(isLoading: true, clearError: true, isGenerating: false, isSlowResponse: false);
    final repo = ref.read(chatRepositoryProvider);
    final conv = await repo.getConversation(id: conversationId);
    final msgs = await repo.getMessages(conversationId: conversationId);
    if (!ref.mounted) return;

    state = ChatState(
      activeConversation: conv,
      messages: msgs,
      isLoading: false,
    );
  }

  Future<void> startNewConversation({RetentionPolicy retentionPolicy = RetentionPolicy.persistent}) async {
    _currentCancellationToken?.cancel();
    _slowTimer?.cancel();
    _coalescingTimer?.cancel();

    if (!ref.mounted) return;
    final convsNotifier = ref.read(conversationsProvider(ownerId).notifier);
    final newConv = await convsNotifier.createNew(retentionPolicy: retentionPolicy);
    if (!ref.mounted) return;

    state = ChatState(
      activeConversation: newConv,
      messages: const [],
      isLoading: false,
    );
  }

  Future<void> deleteActiveConversation() async {
    final active = state.activeConversation;
    if (active == null) return;

    _currentCancellationToken?.cancel();
    final repo = ref.read(chatRepositoryProvider);
    await repo.deleteConversation(id: active.id);
    if (ref.mounted) {
      ref.read(conversationsProvider(ownerId).notifier).refresh();
      await _initialize();
    }
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isGenerating) return;

    final conversation = state.activeConversation;
    if (conversation == null) return;

    final repo = ref.read(chatRepositoryProvider);
    final client = ref.read(chatStreamClientProvider);
    final selectedCategory = ref.read(selectedCategoryProvider(ownerId));

    // Check if category switched since last assistant message, if so add system divider
    final lastAssistant = state.messages.lastWhere(
      (m) => m.role == MessageRole.assistant && m.category != null,
      orElse: () => ChatMessage(
        id: '',
        conversationId: '',
        ownerId: '',
        role: MessageRole.system,
        content: '',
        status: MessageStatus.completed,
        createdAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
    );

    final List<ChatMessage> initialNewMessages = [...state.messages];

    if (lastAssistant.id.isNotEmpty && lastAssistant.category != selectedCategory.id) {
      final dividerMsg = ChatMessage(
        id: 'sys_${DateTime.now().microsecondsSinceEpoch}',
        conversationId: conversation.id,
        ownerId: ownerId,
        role: MessageRole.system,
        content: 'Переключено на категорию: ${selectedCategory.id}',
        status: MessageStatus.completed,
        category: selectedCategory.id,
        createdAtUtc: DateTime.now().toUtc(),
      );
      initialNewMessages.add(dividerMsg);
      if (!conversation.isEphemeral) {
        await repo.saveMessage(dividerMsg);
      }
    }

    // 1. Add User Message
    final now = DateTime.now().toUtc();
    final userMsg = ChatMessage(
      id: 'msg_${now.millisecondsSinceEpoch}_user',
      conversationId: conversation.id,
      ownerId: ownerId,
      role: MessageRole.user,
      content: trimmed,
      status: MessageStatus.completed,
      createdAtUtc: now,
    );
    initialNewMessages.add(userMsg);
    if (!conversation.isEphemeral) {
      await repo.saveMessage(userMsg);
    }

    // Update conversation title if first user message
    if (initialNewMessages.where((m) => m.isUser).length == 1 && conversation.title == 'Новый разговор') {
      final newTitle = trimmed.length > 32 ? '${trimmed.substring(0, 32)}...' : trimmed;
      await repo.updateConversationTitle(id: conversation.id, title: newTitle);
      ref.read(conversationsProvider(ownerId).notifier).refresh();
    }

    // 2. Prepare Context Manifest
    final requestId = CraftAiClient.generateRequestId();
    final assembler = const ContextAssembler();
    final manifest = assembler.assemble(
      manifestId: 'manifest_$requestId',
      requestId: requestId,
      category: selectedCategory.id,
      catalogRevision: '2026-03-31-01',
      contextWindow: 128000,
      conversationHistory: initialNewMessages,
      userPrompt: trimmed,
    );
    await repo.saveContextManifest(manifest);

    // 3. Add Placeholder Assistant Message
    final assistantMsgId = 'msg_${DateTime.now().millisecondsSinceEpoch}_assistant';
    final assistantPlaceholder = ChatMessage(
      id: assistantMsgId,
      conversationId: conversation.id,
      ownerId: ownerId,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
      requestId: requestId,
      category: selectedCategory.id,
      createdAtUtc: DateTime.now().toUtc(),
    );
    initialNewMessages.add(assistantPlaceholder);

    state = state.copyWith(
      messages: initialNewMessages,
      isGenerating: true,
      isSlowResponse: false,
      clearError: true,
    );

    // Start 10s slow response timer
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 10), () {
      if (state.isGenerating) {
        state = state.copyWith(isSlowResponse: true);
      }
    });

    _currentCancellationToken = ChatCancellationToken();
    _bufferedText = '';
    final startTime = DateTime.now().toUtc();
    int? serverPromptTokens;
    int? serverCompletionTokens;

    // Setup coalescing timer (flushes text updates every 50ms)
    _coalescingTimer?.cancel();
    _coalescingTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _flushBufferedText(assistantMsgId);
    });

    try {
      final stream = client.streamCompletion(
        ownerId: ownerId,
        category: selectedCategory.id,
        catalogRevision: '2026-03-31-01',
        messages: manifest.messages,
        requestId: requestId,
        cancellationToken: _currentCancellationToken,
      );

      String currentModelId = selectedCategory.defaultModelId;

      await for (final event in stream) {
        if (event is StartStreamEvent) {
          currentModelId = event.modelId;
          state = state.copyWith(activeModelId: event.modelId);
        } else if (event is TextDeltaStreamEvent) {
          _bufferedText += event.text;
        } else if (event is UsageStreamEvent) {
          serverPromptTokens = event.inputTokens;
          serverCompletionTokens = event.outputTokens;
        } else if (event is TerminalStreamEvent) {
          _slowTimer?.cancel();
          _coalescingTimer?.cancel();
          _flushBufferedText(assistantMsgId);

          final finalStatus = event.isInterrupted
              ? MessageStatus.interrupted
              : (event.isError ? MessageStatus.error : MessageStatus.completed);

          final updatedMessages = state.messages.map((m) {
            if (m.id == assistantMsgId) {
              return m.copyWith(
                content: _bufferedText.isEmpty ? m.content : _bufferedText,
                status: finalStatus,
                modelId: currentModelId,
              );
            }
            return m;
          }).toList();

          state = state.copyWith(
            messages: updatedMessages,
            isGenerating: false,
            isSlowResponse: false,
          );

          final finalMsg = updatedMessages.firstWhere((m) => m.id == assistantMsgId);
          if (!conversation.isEphemeral) {
            await repo.saveMessage(finalMsg);
          }

          // Save Execution Trace
          final durationMs = DateTime.now().toUtc().difference(startTime).inMilliseconds;
          final trace = RequestTrace.fromExecution(
            requestId: requestId,
            ownerId: ownerId,
            conversationId: conversation.id,
            modelCategory: selectedCategory.id,
            assistantVersion: 1,
            userPrompt: trimmed,
            responseText: _bufferedText.isEmpty ? finalMsg.content : _bufferedText,
            durationMs: durationMs,
            status: event.isInterrupted
                ? TraceStatus.interrupted
                : (event.isError ? TraceStatus.error : TraceStatus.completed),
            errorCode: event.isError ? (event.code ?? 'Error') : null,
            createdAtUtc: startTime,
            serverPromptTokens: serverPromptTokens,
            serverCompletionTokens: serverCompletionTokens,
            costTier: selectedCategory.priceRating,
          );
          await ref.read(traceRepositoryProvider).saveTrace(trace);
          break;
        }
      }
    } catch (e) {
      _slowTimer?.cancel();
      _coalescingTimer?.cancel();
      _flushBufferedText(assistantMsgId);

      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      final updatedMessages = state.messages.map((m) {
        if (m.id == assistantMsgId) {
          return m.copyWith(
            status: MessageStatus.error,
            errorMessage: errorMsg,
          );
        }
        return m;
      }).toList();

      state = state.copyWith(
        messages: updatedMessages,
        isGenerating: false,
        isSlowResponse: false,
        error: errorMsg,
      );

      final failedMsg = updatedMessages.firstWhere((m) => m.id == assistantMsgId);
      if (!conversation.isEphemeral) {
        await repo.saveMessage(failedMsg);
      }

      // Save Execution Trace on catch
      final durationMs = DateTime.now().toUtc().difference(startTime).inMilliseconds;
      final trace = RequestTrace.fromExecution(
        requestId: requestId,
        ownerId: ownerId,
        conversationId: conversation.id,
        modelCategory: selectedCategory.id,
        assistantVersion: 1,
        userPrompt: trimmed,
        responseText: _bufferedText,
        durationMs: durationMs,
        status: TraceStatus.error,
        errorCode: errorMsg,
        createdAtUtc: startTime,
        costTier: selectedCategory.priceRating,
      );
      await ref.read(traceRepositoryProvider).saveTrace(trace);
    } finally {
      _slowTimer?.cancel();
      _coalescingTimer?.cancel();
      _currentCancellationToken = null;
    }
  }

  void _flushBufferedText(String assistantMsgId) {
    if (_bufferedText.isEmpty) return;

    final updated = state.messages.map((m) {
      if (m.id == assistantMsgId) {
        return m.copyWith(content: _bufferedText);
      }
      return m;
    }).toList();

    state = state.copyWith(messages: updated);
  }

  void stopGeneration() {
    _currentCancellationToken?.cancel();
    _slowTimer?.cancel();
    _coalescingTimer?.cancel();
  }

  Future<void> retryLast() async {
    if (state.isGenerating) return;

    final msgs = state.messages;
    final lastUserIdx = msgs.lastIndexWhere((m) => m.isUser);
    if (lastUserIdx == -1) return;

    final userPrompt = msgs[lastUserIdx].content;

    // Remove failed assistant message if present
    if (lastUserIdx < msgs.length - 1 && msgs.last.isAssistant && msgs.last.status == MessageStatus.error) {
      final repo = ref.read(chatRepositoryProvider);
      await repo.deleteMessage(id: msgs.last.id);
      final trimmedList = List<ChatMessage>.from(msgs)..removeLast();
      state = state.copyWith(messages: trimmedList);
    }

    await sendMessage(userPrompt);
  }

  Future<void> reportMessage({
    required String requestId,
    required String reason,
    String? comment,
  }) async {
    final repo = ref.read(chatRepositoryProvider);
    await repo.reportMessage(
      requestId: requestId,
      reason: reason,
      comment: comment,
    );

    final updated = state.messages.map((m) {
      if (m.requestId == requestId) {
        return m.copyWith(isReported: true);
      }
      return m;
    }).toList();

    state = state.copyWith(messages: updated);
  }
}

final chatSessionProvider = NotifierProvider.family<ChatSessionNotifier, ChatState, String>(
  ChatSessionNotifier.new,
);
