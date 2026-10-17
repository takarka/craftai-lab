import 'package:flutter/material.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../domain/assistant_config.dart';

Future<bool?> showRollbackConfirmationSheet(
  BuildContext context, {
  required AssistantVersion targetVersion,
  required AssistantConfig? currentConfig,
}) {
  return showBuilderSheet<bool>(
    context,
    title: 'Восстановление версии',
    child: _RollbackConfirmationContent(
      targetVersion: targetVersion,
      currentConfig: currentConfig,
    ),
  );
}

class _RollbackConfirmationContent extends StatelessWidget {
  const _RollbackConfirmationContent({
    required this.targetVersion,
    required this.currentConfig,
  });

  final AssistantVersion targetVersion;
  final AssistantConfig? currentConfig;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final snapshot = targetVersion.snapshot;

    final nameDiffers = currentConfig != null && currentConfig!.name != snapshot.name;
    final catDiffers = currentConfig != null && currentConfig!.selectedCategory != snapshot.selectedCategory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.rollbackDialogTitle(targetVersion.versionNumber),
          style: BuilderType.h3,
        ),
        const SizedBox(height: 6),
        Text(
          s.rollbackDialogSubtitle,
          style: BuilderType.body.copyWith(color: BuilderColors.inkSecondary),
        ),
        const SizedBox(height: 16),

        // What will change
        Text(s.rollbackWhatWillChange, style: BuilderType.title),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BuilderColors.surfaceDisabled,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• Имя: ${nameDiffers ? "${currentConfig!.name} → ${snapshot.name}" : snapshot.name}',
                style: BuilderType.small,
              ),
              const SizedBox(height: 4),
              Text(
                '• Модель: ${catDiffers ? "${currentConfig!.selectedCategory?.name ?? '—'} → ${snapshot.selectedCategory?.name ?? '—'}" : (snapshot.selectedCategory?.name ?? 'По умолчанию')}',
                style: BuilderType.small,
              ),
              const SizedBox(height: 4),
              Text(
                '• Активных умений в снимке: ${snapshot.enabledSkills.length}',
                style: BuilderType.small,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // What will keep
        Text(s.rollbackWhatWillKeep, style: BuilderType.title),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BuilderColors.primaryTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BuilderIcon(BuilderGlyph.check, size: 18, color: BuilderColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.rollbackKeepHistory,
                  style: BuilderType.small.copyWith(color: BuilderColors.primary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Missing resources warning if any
        if (targetVersion.missingResources.isNotEmpty) ...[
          BuilderNotice(
            title: s.assistantVersionMissingResources,
            body: s.rollbackMissingResourcesWarning,
            warning: true,
          ),
          const SizedBox(height: 16),
        ],

        // Action buttons
        Row(
          children: [
            Expanded(
              child: BuilderButton(
                key: const Key('rollback.confirmBtn'),
                label: s.rollbackConfirmButton,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BuilderButton(
                key: const Key('rollback.cancelBtn'),
                label: s.rollbackCancelButton,
                variant: BuilderButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
