import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../assistant_providers.dart';
import '../domain/assistant_config.dart';
import 'rollback_confirmation_sheet.dart';

class AssistantVersionsPage extends ConsumerStatefulWidget {
  const AssistantVersionsPage({super.key, required this.ownerId});

  final String ownerId;

  @override
  ConsumerState<AssistantVersionsPage> createState() =>
      _AssistantVersionsPageState();
}

class _AssistantVersionsPageState extends ConsumerState<AssistantVersionsPage> {
  final _dateFormat = DateFormat('dd.MM.yyyy · HH:mm');

  Future<void> _handleManualSave() async {
    final s = AppLocalizations.of(context);
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.assistantVersionSaveManual),
        content: TextField(
          key: const Key('versions.manualReasonField'),
          controller: reasonController,
          decoration: InputDecoration(
            hintText: s.assistantVersionSaveReasonHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          BuilderButton(
            label: 'Сохранить',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(assistantControllerProvider(widget.ownerId))
          .manualSaveVersion(reasonController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Версия успешно сохранена')),
        );
      }
    }
  }

  Future<void> _handleRollback(
    AssistantVersion version,
    AssistantConfig? currentConfig,
  ) async {
    if (version.isCurrent) return;

    final confirmed = await showRollbackConfirmationSheet(
      context,
      targetVersion: version,
      currentConfig: currentConfig,
    );

    if (confirmed == true && mounted) {
      final s = AppLocalizations.of(context);
      try {
        await ref
            .read(assistantControllerProvider(widget.ownerId))
            .rollbackToVersion(version.versionNumber);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.rollbackSuccess(version.versionNumber))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка при восстановлении: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final versionsAsync = ref.watch(assistantVersionsProvider(widget.ownerId));
    final currentConfigAsync = ref.watch(
      assistantConfigProvider(widget.ownerId),
    );
    final currentConfig = currentConfigAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.assistantVersionsTitle, style: BuilderType.h3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton.icon(
            key: const Key('versions.manualSaveBtn'),
            icon: const Icon(Icons.bookmark_add_outlined, size: 20),
            label: Text(s.assistantVersionSaveManual),
            onPressed: _handleManualSave,
          ),
        ],
      ),
      body: SafeArea(
        child: versionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) =>
              Center(child: Text('Ошибка загрузки версий: $err')),
          data: (versions) {
            if (versions.isEmpty) {
              return Center(
                child: Text(
                  'История версий пуста',
                  style: BuilderType.body.copyWith(
                    color: BuilderColors.inkSecondary,
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: versions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final v = versions[index];
                return _VersionTile(
                  version: v,
                  formattedDate: _dateFormat.format(v.createdAtUtc.toLocal()),
                  onTap: () => _handleRollback(v, currentConfig),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.version,
    required this.formattedDate,
    required this.onTap,
  });

  final AssistantVersion version;
  final String formattedDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return BuilderCard(
      key: Key('version.card.${version.versionNumber}'),
      selected: version.isCurrent,
      onTap: version.isCurrent ? null : onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: version.isCurrent
                      ? BuilderColors.primary
                      : BuilderColors.surfaceDisabled,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'v${version.versionNumber}',
                  style: BuilderType.small.copyWith(
                    color: version.isCurrent ? Colors.white : BuilderColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (version.isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: BuilderColors.primaryTint,
                    borderRadius: BorderRadius.circular(BuilderRadii.chip),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BuilderIcon(
                        BuilderGlyph.check,
                        size: 15,
                        color: BuilderColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.assistantVersionCurrent,
                        style: BuilderType.small.copyWith(
                          color: BuilderColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              Text(
                formattedDate,
                style: BuilderType.small.copyWith(
                  color: BuilderColors.inkSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(version.reason, style: BuilderType.title),
          const SizedBox(height: 6),
          Text(
            'Имя: ${version.snapshot.name} · Модель: ${version.snapshot.selectedCategory?.name ?? 'По умолчанию'} · Умений: ${version.snapshot.enabledSkills.length}',
            style: BuilderType.small.copyWith(
              color: BuilderColors.inkSecondary,
            ),
          ),
          if (version.missingResources.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: BuilderColors.warning,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    s.assistantVersionMissingResources,
                    style: BuilderType.small.copyWith(
                      color: BuilderColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
