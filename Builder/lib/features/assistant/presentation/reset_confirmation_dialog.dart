import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../assistant_providers.dart';

Future<void> showResetConfirmationDialog(
  BuildContext context, {
  required String ownerId,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ResetConfirmationDialog(ownerId: ownerId),
  );
}

class _ResetConfirmationDialog extends ConsumerStatefulWidget {
  const _ResetConfirmationDialog({required this.ownerId});

  final String ownerId;

  @override
  ConsumerState<_ResetConfirmationDialog> createState() => _ResetConfirmationDialogState();
}

class _ResetConfirmationDialogState extends ConsumerState<_ResetConfirmationDialog> {
  final _textController = TextEditingController();
  bool _isResetting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _handleReset() async {
    if (_isResetting) return;

    setState(() {
      _isResetting = true;
    });

    try {
      await ref.read(assistantControllerProvider(widget.ownerId)).resetWorkspace();
      if (mounted) {
        Navigator.of(context).pop();
        context.go('/onboarding/assistant');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isResetting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при сбросе: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final confirmWord = s.resetConfirmationWord.toUpperCase();
    final typedWord = _textController.text.trim().toUpperCase();
    final isWordMatched = typedWord == confirmWord;

    return AlertDialog(
      title: Row(
        children: [
          const BuilderIcon(BuilderGlyph.trash, color: BuilderColors.warning, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.resetDialogTitle,
              style: BuilderType.h3.copyWith(color: BuilderColors.warning),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.resetDialogSubtitle,
                style: BuilderType.body.copyWith(color: BuilderColors.inkSecondary),
              ),
              const SizedBox(height: 16),

              // What will be deleted
              Text(s.resetWhatWillBeDeleted, style: BuilderType.title),
              const SizedBox(height: 6),
              _item(s.resetDeleteInstructions, isDeleted: true),
              _item(s.resetDeleteConversations, isDeleted: true),
              _item(s.resetDeleteMemory, isDeleted: true),
              _item(s.resetDeleteDocuments, isDeleted: true),
              _item(s.resetDeleteVersions, isDeleted: true),
              _item(s.resetDeleteTraces, isDeleted: true),

              const SizedBox(height: 12),

              // What will stay
              Text(s.resetWhatWillStay, style: BuilderType.title),
              const SizedBox(height: 6),
              _item(s.resetKeepAccount, isDeleted: false),
              _item(s.resetKeepD02, isDeleted: false),

              const SizedBox(height: 16),

              // Strong confirmation input (F09-10 & F09-V02)
              Text(
                s.resetTypeConfirmationPrompt(confirmWord),
                style: BuilderType.small.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('reset.confirmationWordField'),
                controller: _textController,
                enabled: !_isResetting,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: confirmWord,
                  errorText: typedWord.isNotEmpty && !isWordMatched ? 'Введите «$confirmWord»' : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('reset.cancelBtn'),
          onPressed: _isResetting ? null : () => Navigator.of(context).pop(),
          child: Text(s.resetCancelButton),
        ),
        BuilderButton(
          key: const Key('reset.confirmBtn'),
          label: s.resetConfirmButton,
          variant: BuilderButtonVariant.dangerFilled,
          loading: _isResetting,
          loadingLabel: s.resetInProgress,
          onPressed: isWordMatched ? _handleReset : null,
        ),
      ],
    );
  }

  Widget _item(String text, {required bool isDeleted}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isDeleted ? Icons.close : Icons.check,
            size: 16,
            color: isDeleted ? BuilderColors.warning : BuilderColors.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: BuilderType.small.copyWith(
                color: isDeleted ? BuilderColors.ink : BuilderColors.inkSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
