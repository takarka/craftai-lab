import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isGenerating;
  final bool isModelLoaded;
  final bool enableThinking;
  final ValueChanged<bool> onToggleThinking;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.isGenerating,
    required this.isModelLoaded,
    required this.enableThinking,
    required this.onToggleThinking,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thinking Toggle Chip
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: isModelLoaded
                      ? () => onToggleThinking(!enableThinking)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: enableThinking
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: enableThinking
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.psychology_rounded,
                          size: 16,
                          color: enableThinking
                              ? theme.colorScheme.primary
                              : theme.iconTheme.color?.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          enableThinking ? 'Рассуждения: Вкл' : 'Рассуждения: Выкл',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: enableThinking
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: enableThinking
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  enableThinking
                      ? 'Модель выводит ход мыслей'
                      : 'Прямые быстрые ответы',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Input Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  enabled: isModelLoaded,
                  decoration: InputDecoration(
                    hintText: isModelLoaded
                        ? 'Спросите что-нибудь у Qwen...'
                        : 'Сначала загрузите модель...',
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) {
                    if (isModelLoaded && !isGenerating) {
                      onSend();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Container(
                margin: const EdgeInsets.only(bottom: 2),
                child: FloatingActionButton.small(
                  elevation: 0,
                  highlightElevation: 0,
                  backgroundColor: isGenerating
                      ? Colors.redAccent
                      : (isModelLoaded
                          ? theme.colorScheme.primary
                          : theme.disabledColor),
                  foregroundColor: Colors.white,
                  onPressed: !isModelLoaded
                      ? null
                      : (isGenerating ? onStop : onSend),
                  child: Icon(
                    isGenerating ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
