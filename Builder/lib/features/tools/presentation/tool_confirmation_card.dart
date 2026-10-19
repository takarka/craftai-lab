import 'package:flutter/material.dart';

import '../../../ui_kit/controls.dart';
import '../../../ui_kit/identity.dart';
import '../../../ui_kit/tokens.dart';
import '../domain/pending_action.dart';

/// Confirmation card widget for chat or S43 with double-tap protection and min 44x44 targets (F14-05, F14-12).
class ToolConfirmationCard extends StatefulWidget {
  final PendingAction action;
  final Future<void> Function(String invocationId) onConfirm;
  final Future<void> Function(String invocationId) onReject;

  const ToolConfirmationCard({
    super.key,
    required this.action,
    required this.onConfirm,
    required this.onReject,
  });

  @override
  State<ToolConfirmationCard> createState() => _ToolConfirmationCardState();
}

class _ToolConfirmationCardState extends State<ToolConfirmationCard> {
  bool _isProcessing = false;

  Future<void> _handleConfirm() async {
    if (_isProcessing || !widget.action.canBeDecided) return;
    setState(() => _isProcessing = true);
    try {
      await widget.onConfirm(widget.action.invocationId);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleReject() async {
    if (_isProcessing || !widget.action.canBeDecided) return;
    setState(() => _isProcessing = true);
    try {
      await widget.onReject(widget.action.invocationId);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final isDecided = !action.canBeDecided;

    return Container(
      key: Key('tool.confirmation.${action.invocationId}'),
      margin: const EdgeInsets.symmetric(vertical: BuilderSpace.xs),
      padding: const EdgeInsets.all(BuilderSpace.md),
      decoration: BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.circular(BuilderRadii.card),
        border: Border.all(
          color: action.status == PendingActionStatus.pending
              ? BuilderColors.primary
              : BuilderColors.line,
          width: action.status == PendingActionStatus.pending ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuilderIcon(
                BuilderGlyph.tool,
                size: 20,
                color: BuilderColors.primary,
              ),
              const SizedBox(width: BuilderSpace.xs),
              Expanded(
                child: Text(
                  _getActionTitle(action.actionName),
                  style: BuilderTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: BuilderColors.ink,
                  ),
                ),
              ),
              _buildStatusBadge(action.status),
            ],
          ),
          const SizedBox(height: BuilderSpace.xs),

          // Parameters inspection (F14-05)
          Container(
            padding: const EdgeInsets.all(BuilderSpace.sm),
            decoration: BoxDecoration(
              color: BuilderColors.background,
              borderRadius: BorderRadius.circular(BuilderRadii.tile),
              border: Border.all(color: BuilderColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...action.params.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_formatParamKey(entry.key)}: ',
                          style: BuilderTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: BuilderColors.inkSecondary,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${entry.value}',
                            style: BuilderTypography.bodySmall.copyWith(
                              color: BuilderColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: BuilderSpace.sm),

          // Action Buttons with guaranteed 44x44 minimum hit target
          if (!isDecided) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: Key('tool.rejectBtn.${action.invocationId}'),
                  onPressed: _isProcessing ? null : _handleReject,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    foregroundColor: BuilderColors.inkSecondary,
                  ),
                  child: const Text('Отклонить'),
                ),
                const SizedBox(width: BuilderSpace.xs),
                BuilderButton(
                  key: Key('tool.confirmBtn.${action.invocationId}'),
                  label: _isProcessing ? 'Выполнение...' : 'Подтвердить',
                  loading: _isProcessing,
                  onPressed: _handleConfirm,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _getActionTitle(String name) {
    switch (name) {
      case 'create_calendar_event':
        return 'Запрос на создание события';
      case 'delete_note':
        return 'Запрос на удаление заметки';
      default:
        return 'Подтверждение действия: $name';
    }
  }

  String _formatParamKey(String key) {
    switch (key) {
      case 'title':
        return 'Название';
      case 'start_time':
        return 'Начало';
      case 'end_time':
        return 'Окончание';
      case 'location':
        return 'Место';
      case 'notes':
        return 'Заметки';
      case 'reminder_minutes':
        return 'Напомнить за (мин)';
      default:
        return key;
    }
  }

  Widget _buildStatusBadge(PendingActionStatus status) {
    Color bg;
    Color fg;
    switch (status) {
      case PendingActionStatus.pending:
        bg = BuilderColors.primaryTint;
        fg = BuilderColors.primary;
        break;
      case PendingActionStatus.approved:
      case PendingActionStatus.executed:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        break;
      case PendingActionStatus.rejected:
      case PendingActionStatus.expired:
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.label,
        style: BuilderTypography.bodySmall.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
