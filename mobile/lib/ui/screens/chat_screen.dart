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
  final List<ChatMessage> _messages = [];

  @override
  void dispose() {
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
    if (text.isEmpty) return;

    if (!widget.llmService.isModelLoaded) {
      _openModelManagement();
      return;
    }

    _inputController.clear();

    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    final aiMessageId = (DateTime.now().millisecondsSinceEpoch + 1).toString();
    final aiMessage = ChatMessage(
      id: aiMessageId,
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      isGenerating: true,
    );

    setState(() {
      _messages.add(userMessage);
      _messages.add(aiMessage);
    });

    _scrollToBottom();

    final StringBuffer buffer = StringBuffer();

    try {
      final stream = widget.llmService.generateResponseStream(
        userPrompt: text,
      );

      await for (final token in stream) {
        buffer.write(token);
        final currentText = buffer.toString();

        final index = _messages.indexWhere((m) => m.id == aiMessageId);
        if (index != -1 && mounted) {
          setState(() {
            _messages[index] = _messages[index].copyWith(
              text: currentText,
              tokensPerSecond: widget.llmService.lastTokensPerSecond,
              totalTokens: widget.llmService.lastTokenCount,
            );
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      buffer.write('\n\n⚠️ *Ошибка при генерации:* $e');
    } finally {
      final index = _messages.indexWhere((m) => m.id == aiMessageId);
      if (index != -1 && mounted) {
        setState(() {
          _messages[index] = _messages[index].copyWith(
            text: buffer.toString(),
            isGenerating: false,
            tokensPerSecond: widget.llmService.lastTokensPerSecond,
            totalTokens: widget.llmService.lastTokenCount,
          );
        });
      }
    }
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить диалог?'),
        content: const Text('Вся история сообщений текущей сессии будет удалена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _messages.clear();
              });
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
            icon: const Icon(Icons.settings_suggest_rounded),
            tooltip: 'Модели',
            onPressed: _openModelManagement,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Очистить чат',
            onPressed: _messages.isEmpty ? null : _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(theme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return ChatBubble(message: _messages[index]);
                    },
                  ),
          ),
          ListenableBuilder(
            listenable: llm,
            builder: (context, _) {
              return ChatInputBar(
                controller: _inputController,
                isGenerating: llm.isGenerating,
                isModelLoaded: llm.isModelLoaded,
                onSend: _sendMessage,
                onStop: () => llm.stopGeneration(),
              );
            },
          ),
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
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
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
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
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
                    onPressed: () => _sendMessage('Объясни квантовые вычисления простыми словами'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.code_rounded, size: 16),
                    label: const Text('Напиши функцию на Dart'),
                    onPressed: () => _sendMessage('Напиши функцию на Dart для вычисления чисел Фибоначчи'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.phone_android_rounded, size: 16),
                    label: const Text('Как работает локальная LLM?'),
                    onPressed: () => _sendMessage('Как работает локальная языковая модель прямо на смартфоне?'),
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
