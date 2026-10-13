import 'package:flutter/material.dart';

class GenerationStatsBadge extends StatelessWidget {
  final bool isModelLoaded;
  final String modelName;
  final bool isGenerating;
  final double tokensPerSecond;
  final VoidCallback onTap;

  const GenerationStatsBadge({
    super.key,
    required this.isModelLoaded,
    required this.modelName,
    required this.isGenerating,
    required this.tokensPerSecond,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isModelLoaded
                ? Colors.green.withValues(alpha: 0.5)
                : Colors.amber.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isModelLoaded ? Colors.greenAccent : Colors.amberAccent,
                boxShadow: [
                  BoxShadow(
                    color: (isModelLoaded ? Colors.greenAccent : Colors.amberAccent)
                        .withValues(alpha: 0.6),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                isModelLoaded
                    ? (isGenerating && tokensPerSecond > 0
                        ? '${tokensPerSecond.toStringAsFixed(1)} tok/s'
                        : modelName)
                    : 'Модель не выбрана',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16),
          ],
        ),
      ),
    );
  }
}
