import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isGenerating;
  final bool isModelLoaded;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.isGenerating,
    required this.isModelLoaded,
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
        top: 10,
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
      child: Row(
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
    );
  }
}
