import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../assistant_providers.dart';
import '../domain/assistant_config.dart';
import 'reset_confirmation_dialog.dart';

class AssistantSettingsPage extends ConsumerWidget {
  const AssistantSettingsPage({super.key, required this.ownerId});

  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context);
    final configAsync = ref.watch(assistantConfigProvider(ownerId));
    final versionsAsync = ref.watch(assistantVersionsProvider(ownerId));
    final summaryAsync = ref.watch(localDataSummaryProvider(ownerId));
    final completedLevelsAsync = ref.watch(completedCourseLevelsProvider(ownerId));

    final config = configAsync.asData?.value;
    final versions = versionsAsync.asData?.value ?? [];
    final summary = summaryAsync.asData?.value;
    final completedLevels = completedLevelsAsync.asData?.value ?? {1};

    final currentVersionNumber = versions.isNotEmpty ? versions.first.versionNumber : 1;
    final highestLevel = completedLevels.fold<int>(1, (max, lvl) => lvl > max ? lvl : max);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.assistantSettingsTitle, style: BuilderType.h3),
        leading: IconButton(
          key: const Key('assistantSettings.backBtn'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Character & Name card (F09-V01, F09-02)
              BuilderCard(
                child: Row(
                  children: [
                    const BuilderCharacter(size: 56, compact: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            config?.name.isNotEmpty == true ? config!.name : 'Ассистент',
                            style: BuilderType.h3,
                          ),
                          const SizedBox(height: 4),
                          BuilderBadge(
                            s.assistantLevelBadge(highestLevel),
                            icon: BuilderGlyph.course,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const Key('assistantSettings.editNameBtn'),
                      tooltip: s.assistantEditName,
                      icon: const Icon(Icons.edit_outlined),
                      color: BuilderColors.primary,
                      onPressed: () => context.push('/assistant/settings/name'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. Model row (F09-V01) -> links to S33
              BuilderLinkRow(
                key: const Key('assistantSettings.modelRow'),
                title: s.assistantModelRowTitle,
                subtitle: config?.selectedCategory?.name != null
                    ? '${config!.selectedCategory!.name} · Данные за рубежом'
                    : 'Рабочая (по умолчанию) · Данные за рубежом',
                icon: BuilderGlyph.bolt,
                onTap: () => context.push('/assistant/models'),
              ),
              const SizedBox(height: 12),

              // 3. Instructions card with Versions link (F09-V01)
              BuilderCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const BuilderIconTile(BuilderGlyph.doc),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.assistantInstructionsCardTitle, style: BuilderType.title),
                              const SizedBox(height: 2),
                              Text(s.assistantInstructionsCardSubtitle, style: BuilderType.small.copyWith(color: BuilderColors.inkSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      key: const Key('assistantSettings.versionsLink'),
                      onTap: () => context.push('/assistant/settings/versions'),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: BuilderColors.surfaceDisabled,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const BuilderIcon(BuilderGlyph.code, size: 16, color: BuilderColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.assistantVersionsLink(currentVersionNumber),
                                style: BuilderType.small.copyWith(
                                  color: BuilderColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right, size: 18, color: BuilderColors.inkSecondary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 4. Memory card (F09-V01)
              BuilderCard(
                child: Row(
                  children: [
                    const BuilderIconTile(BuilderGlyph.memory),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.assistantMemoryCardTitle, style: BuilderType.title),
                          const SizedBox(height: 2),
                          Text(
                            summary != null
                                ? '${summary.memoryFactsCount} сохранённых фактов'
                                : s.assistantMemoryCardSubtitle,
                            style: BuilderType.small.copyWith(color: BuilderColors.inkSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 5. Documents / Knowledge card (F09-V01)
              BuilderCard(
                child: Row(
                  children: [
                    const BuilderIconTile(BuilderGlyph.doc, warm: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.assistantDocumentsCardTitle, style: BuilderType.title),
                          const SizedBox(height: 2),
                          Text(
                            summary != null
                                ? '${summary.documentsCount} документов (${summary.chunksCount} фрагментов)'
                                : s.assistantDocumentsCardSubtitle,
                            style: BuilderType.small.copyWith(color: BuilderColors.inkSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 6. Skills domain states (F09-01) - 8 skills (6-9 Скоро)
              Text(s.assistantSkillsHeader, style: BuilderType.h3),
              const SizedBox(height: 12),
              for (final skill in AssistantSkillId.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildSkillCard(context, ref, skill, config, completedLevels),
                ),
              const SizedBox(height: 16),

              // 7. Undo last change button (F09-12)
              if (versions.length > 1) ...[
                SizedBox(
                  width: double.infinity,
                  child: BuilderButton(
                    key: const Key('assistantSettings.undoBtn'),
                    label: s.assistantUndoLastChange,
                    variant: BuilderButtonVariant.secondary,
                    icon: BuilderGlyph.back,
                    onPressed: () async {
                      try {
                        await ref.read(assistantControllerProvider(ownerId)).undoLastChange();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Последнее изменение отменено')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка: $e')),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 8. Device storage & local data map row (S15)
              BuilderLinkRow(
                key: const Key('assistantSettings.localDataRow'),
                title: s.assistantLocalDataRowTitle,
                subtitle: s.assistantLocalDataRowSubtitle,
                icon: BuilderGlyph.reset,
                onTap: () => context.push('/assistant/settings/data'),
              ),
              const SizedBox(height: 16),

              // 9. Full reset action (D05 / F09-11)
              SizedBox(
                width: double.infinity,
                child: BuilderButton(
                  key: const Key('assistantSettings.resetBtn'),
                  label: s.assistantResetButton,
                  variant: BuilderButtonVariant.danger,
                  icon: BuilderGlyph.trash,
                  onPressed: () => showResetConfirmationDialog(context, ownerId: ownerId),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkillCard(
    BuildContext context,
    WidgetRef ref,
    AssistantSkillId skill,
    AssistantConfig? config,
    Set<int> completedLevels,
  ) {
    final isLevelUnlocked = completedLevels.contains(skill.level);
    final isEnabled = config?.enabledSkills.contains(skill.id) ?? false;

    final SkillStatus status;
    if (skill.comingSoon) {
      status = SkillStatus.comingSoon;
    } else if (!isLevelUnlocked) {
      status = SkillStatus.locked;
    } else if (isEnabled) {
      status = SkillStatus.enabled;
    } else {
      status = SkillStatus.disabled;
    }

    return BuilderSkillCard(
      key: Key('skill.card.${skill.id}'),
      title: skill.title,
      subtitle: skill.subtitle,
      icon: skill.glyph,
      status: status,
      level: skill.level,
      onChanged: (status == SkillStatus.enabled || status == SkillStatus.disabled)
          ? (val) {
              ref.read(assistantControllerProvider(ownerId)).toggleSkill(skill, val);
            }
          : null,
    );
  }
}
