import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/chat_message.dart';

class ChatBubble extends StatefulWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _isThoughtExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(
                Icons.auto_awesome,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.82,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isUser
                      ? Text(
                          message.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        )
                      : _buildAiResponse(context, theme, message),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isUser &&
                        message.tokensPerSecond != null &&
                        message.tokensPerSecond! > 0) ...[
                      Text(
                        '${message.tokensPerSecond!.toStringAsFixed(1)} tok/s',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.textTheme.bodySmall?.color?.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: message.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Скопировано в буфер обмена'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: theme.textTheme.bodySmall?.color?.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(
                Icons.person,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiResponse(
    BuildContext context,
    ThemeData theme,
    ChatMessage message,
  ) {
    final rawText = message.text;

    if (rawText.isEmpty && message.reasoning.isEmpty && message.isGenerating) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Генерирую ответ...',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      );
    }

    if (message.reasoning.isNotEmpty) {
      final isStillThinking = message.isGenerating && rawText.isEmpty;
      final thoughtContent = message.reasoning;
      final answerContent = rawText;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collapsible Reasoning Card
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _isThoughtExpanded = !_isThoughtExpanded;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.psychology_rounded,
                          size: 18,
                          color: isStillThinking
                              ? Colors.amberAccent
                              : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isStillThinking
                                ? 'Обдумываю ответ...'
                                : 'Рассуждение модели',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isStillThinking
                                  ? Colors.amberAccent
                                  : theme.textTheme.labelMedium?.color,
                            ),
                          ),
                        ),
                        if (isStillThinking)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            _isThoughtExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                          ),
                      ],
                    ),
                  ),
                ),
                if ((_isThoughtExpanded || isStillThinking) &&
                    thoughtContent.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 12,
                      bottom: 10,
                    ),
                    child: Text(
                      thoughtContent,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                        color: theme.textTheme.bodySmall?.color?.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (message.error != null) _buildError(theme, message.error!),

          // Main Final Answer
          if (answerContent.isNotEmpty) _buildMarkdown(theme, answerContent),

          if (message.isGenerating && !isStillThinking)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
        ],
      );
    }

    // Standard Response without <think>
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rawText.isNotEmpty) _buildMarkdown(theme, rawText),
        if (message.error != null) _buildError(theme, message.error!),
        if (message.isGenerating)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMarkdown(ThemeData theme, String text) {
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.7),
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme, String error) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Ошибка при генерации: $error',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}
