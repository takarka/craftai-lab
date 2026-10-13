import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../services/llm_service.dart';
import '../../services/model_manager_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/generation_stats_badge.dart';
import 'model_management_screen.dart';

class ChatScreen extends StatefulWidget {
  final LLMService llmService;
  final ModelManagerService modelManager;

  const ChatScreen({
    super.key,
    required this.llmService,
    required this.modelManager,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> get _messages => widget.llmService.messages;

  @override
  void initState() {
    super.initState();
    widget.llmService.addListener(_onChatChanged);
  }

  void _onChatChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollToBottom();
  }

  @override
  void dispose() {
    widget.llmService.removeListener(_onChatChanged);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage([String? quickText]) async {
    final text = quickText ?? _inputController.text.trim();
    if (text.isEmpty || !widget.llmService.historyReady) return;

    if (!widget.llmService.isModelLoaded) {
      _openModelManagement();
      return;
    }

    if (widget.llmService.isGenerating || widget.llmService.isLoadingModel) {
      return;
    }
    _inputController.clear();
    try {
      await for (final _ in widget.llmService.generateResponseStream(
        userPrompt: text,
      )) {
        // The service publishes message updates through its listener.
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить диалог?'),
        content: const Text('Сообщения этого чата будут удалены с устройства.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              widget.llmService.resetChatSession();
              Navigator.pop(ctx);
            },
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
  }

  void _openModelManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ModelManagementScreen(
          modelManager: widget.modelManager,
          llmService: widget.llmService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final llm = widget.llmService;

    return Scaffold(
      drawer: _buildChatDrawer(),
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: llm,
          builder: (context, _) {
            return GenerationStatsBadge(
              isModelLoaded: llm.isModelLoaded,
              modelName: llm.currentModelName,
              isGenerating: llm.isGenerating,
              tokensPerSecond: llm.lastTokensPerSecond,
              onTap: _openModelManagement,
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'Новый чат',
            onPressed: llm.canChangeChat
                ? () {
                    _inputController.clear();
                    llm.createNewChat();
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.settings_suggest_rounded),
            tooltip: 'Модели',
            onPressed: _openModelManagement,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Очистить чат',
            onPressed: _messages.isEmpty || !llm.historyReady
                ? null
                : _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!llm.historyReady) const LinearProgressIndicator(),
          if (llm.storageError != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                llm.storageError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          _buildContextIndicator(theme),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(theme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return ChatBubble(
                        key: ValueKey(_messages[index].id),
                        message: _messages[index],
                      );
                    },
                  ),
          ),
          ListenableBuilder(
            listenable: llm,
            builder: (context, _) {
              return ChatInputBar(
                controller: _inputController,
                isGenerating: llm.isGenerating,
                isModelLoaded:
                    llm.isModelLoaded &&
                    llm.historyReady &&
                    !llm.isLoadingModel,
                enableThinking: llm.enableThinking,
                onToggleThinking: (val) => llm.setEnableThinking(val),
                enableWebSearch: llm.enableWebSearch,
                onToggleWebSearch: (val) => llm.setEnableWebSearch(val),
                searchStatus: llm.searchStatus.isNotEmpty
                    ? llm.searchStatus
                    : llm.contextStatus,
                onSend: _sendMessage,
                onStop: () => llm.stopGeneration(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChatDrawer() {
    final llm = widget.llmService;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Чаты на устройстве',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('Новый чат'),
              enabled: llm.canChangeChat,
              onTap: () {
                _inputController.clear();
                llm.createNewChat();
                Navigator.pop(context);
              },
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: llm.conversations.length,
                itemBuilder: (context, index) {
                  final chat = llm.conversations[index];
                  return ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(
                      chat.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${chat.messages.length} сообщений'),
                    selected: chat.id == llm.activeConversation.id,
                    enabled: llm.canChangeChat,
                    onTap: () {
                      _inputController.clear();
                      llm.selectChat(chat.id);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextIndicator(ThemeData theme) {
    final llm = widget.llmService;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            llm.activeConversation.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          if (llm.isModelLoaded) ...[
            const SizedBox(height: 4),
            Tooltip(
              message:
                  'Токены последнего запроса без генерируемого ответа. '
                  'При заполнении контекста старые сообщения заменяются кратким резюме.',
              child: Text(
                'Контекст запроса: ${llm.contextTokens} / ${llm.contextSize} токенов${llm.activeConversation.summary.isEmpty ? '' : ' • с резюме'}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: (llm.contextTokens / llm.contextSize).clamp(0.0, 1.0),
              minHeight: 3,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.smart_toy_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Qwen On-Device AI',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Автономный локальный искусственный интеллект на вашем телефоне. '
              'Без интернета, без задержек API, 100% конфиденциально.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(
                  alpha: 0.7,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (!widget.llmService.isModelLoaded)
              FilledButton.icon(
                onPressed: _openModelManagement,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Загрузить модель GGUF'),
              )
            else ...[
              Text(
                'Быстрые подсказки:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.lightbulb_outline, size: 16),
                    label: const Text('Объясни квантовые вычисления'),
                    onPressed: () => _sendMessage(
                      'Объясни квантовые вычисления простыми словами',
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.code_rounded, size: 16),
                    label: const Text('Напиши функцию на Dart'),
                    onPressed: () => _sendMessage(
                      'Напиши функцию на Dart для вычисления чисел Фибоначчи',
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.phone_android_rounded, size: 16),
                    label: const Text('Как работает локальная LLM?'),
                    onPressed: () => _sendMessage(
                      'Как работает локальная языковая модель прямо на смартфоне?',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
