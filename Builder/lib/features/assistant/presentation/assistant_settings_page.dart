import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../../onboarding/domain/assistant_setup.dart';
import '../../onboarding/presentation/onboarding_labels.dart';
import '../../profile/profile_providers.dart';
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
    final completedLevelsAsync = ref.watch(
      completedCourseLevelsProvider(ownerId),
    );

    final config = configAsync.asData?.value;
    final versions = versionsAsync.asData?.value ?? [];
    final completedLevels = completedLevelsAsync.asData?.value ?? const {};

    final currentVersionNumber = versions.isNotEmpty
        ? versions.first.versionNumber
        : 1;
    final highestLevel = completedLevels.fold<int>(
      0,
      (max, lvl) => lvl > max ? lvl : max,
    );
    final preferences = ref
        .watch(teacherPreferencesProvider(ownerId))
        .asData
        ?.value;
    final assistantLanguage =
        preferences?.setup.language ?? AssistantLanguage.russian;

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
                    BuilderCharacter(
                      level: highestLevel,
                      size: 56,
                      compact: true,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            config?.name.isNotEmpty == true
                                ? config!.name
                                : 'Ассистент',
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

              // 2b. Assistant Language row (F16-04)
              BuilderLinkRow(
                key: const Key('assistantSettings.languageRow'),
                title: 'Язык ответов ассистента',
                subtitle:
                    '${languageLabel(assistantLanguage, s)} · Создаёт новую версию',
                icon: BuilderGlyph.globe,
                onTap: () => _showLanguageSelectionSheet(
                  context,
                  ref,
                  ownerId,
                  assistantLanguage,
                  currentVersionNumber,
                ),
              ),
              const SizedBox(height: 12),

              BuilderLinkRow(
                key: const Key('assistantSettings.versionsLink'),
                title: s.assistantVersionsLink(currentVersionNumber),
                subtitle: Localizations.localeOf(context).languageCode == 'kk'
                    ? 'Өзгерістер тарихы және қалпына келтіру'
                    : 'История изменений и восстановление',
                icon: BuilderGlyph.code,
                onTap: () => context.push('/assistant/settings/versions'),
              ),
              const SizedBox(height: 24),

              // 6. Skills domain states (F09-01) - 8 skills (6-9 Скоро)
              Text(s.assistantSkillsHeader, style: BuilderType.h3),
              const SizedBox(height: 12),
              for (final skill in AssistantSkillId.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildSkillCard(
                    context,
                    ref,
                    skill,
                    config,
                    completedLevels,
                  ),
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
                        await ref
                            .read(assistantControllerProvider(ownerId))
                            .undoLastChange();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Последнее изменение отменено'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
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
                  onPressed: () =>
                      showResetConfirmationDialog(context, ownerId: ownerId),
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
      level: skill.displayLevel,
      onChanged:
          (status == SkillStatus.enabled || status == SkillStatus.disabled)
          ? (val) {
              ref
                  .read(assistantControllerProvider(ownerId))
                  .toggleSkill(skill, val);
            }
          : null,
      onTap: (status == SkillStatus.enabled || status == SkillStatus.disabled)
          ? () {
              if (skill == AssistantSkillId.instructions &&
                  (status == SkillStatus.enabled ||
                      status == SkillStatus.disabled)) {
                context.push('/assistant/instructions');
              } else if (skill == AssistantSkillId.knowledge &&
                  (status == SkillStatus.enabled ||
                      status == SkillStatus.disabled)) {
                context.push('/assistant/knowledge');
              } else if (skill == AssistantSkillId.memory &&
                  (status == SkillStatus.enabled ||
                      status == SkillStatus.disabled)) {
                context.push('/assistant/memory');
              } else if (skill == AssistantSkillId.tools &&
                  (status == SkillStatus.enabled ||
                      status == SkillStatus.disabled)) {
                context.push('/assistant/tools');
              }
            }
          : null,
    );
  }

  void _showLanguageSelectionSheet(
    BuildContext context,
    WidgetRef ref,
    String ownerId,
    AssistantLanguage currentLanguage,
    int currentVersion,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AssistantLanguageSheet(
        ownerId: ownerId,
        currentLanguage: currentLanguage,
        currentVersion: currentVersion,
      ),
    );
  }
}

class _AssistantLanguageSheet extends ConsumerStatefulWidget {
  final String ownerId;
  final AssistantLanguage currentLanguage;
  final int currentVersion;

  const _AssistantLanguageSheet({
    required this.ownerId,
    required this.currentLanguage,
    required this.currentVersion,
  });

  @override
  ConsumerState<_AssistantLanguageSheet> createState() =>
      _AssistantLanguageSheetState();
}

class _AssistantLanguageSheetState
    extends ConsumerState<_AssistantLanguageSheet> {
  late AssistantLanguage _selectedLanguage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.currentLanguage;
  }

  Future<void> _applyLanguage() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(assistantControllerProvider(widget.ownerId))
          .saveLanguage(_selectedLanguage);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Язык ассистента обновлён (создана версия v${widget.currentVersion + 1})',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка обновления языка: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final nextVersion = widget.currentVersion + 1;

    return Container(
      decoration: const BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BuilderRadii.sheet),
        ),
      ),
      padding: const EdgeInsets.all(BuilderSpace.lg),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: BuilderColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: BuilderSpace.md),
            Text('Язык ответов ассистента', style: BuilderType.h3),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(BuilderSpace.sm),
              decoration: BoxDecoration(
                color: BuilderColors.primaryTint,
                borderRadius: BorderRadius.circular(BuilderRadii.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: BuilderIcon(
                      BuilderGlyph.info,
                      size: 18,
                      color: BuilderColors.primary,
                    ),
                  ),
                  const SizedBox(width: BuilderSpace.xs),
                  Expanded(
                    child: Text(
                      'Смена языка создаст новую версию ассистента (v$nextVersion). '
                      'Ассистент начнёт формулировать ответы и генерировать материалы на выбранном языке. '
                      'Сохранённые диалоги, память и документы останутся на месте.',
                      style: BuilderType.small.copyWith(
                        color: BuilderColors.primary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildLanguageOption(
              key: const Key('assistantLanguage.radio.russian'),
              title: s.onbRussian,
              subtitle: 'Ответы и планы уроков на русском языке',
              value: AssistantLanguage.russian,
            ),
            _buildLanguageOption(
              key: const Key('assistantLanguage.radio.kazakh'),
              title: s.onbKazakh,
              subtitle: 'Барлық жауаптар мен сабақ жоспарлары қазақ тілінде',
              value: AssistantLanguage.kazakh,
            ),
            _buildLanguageOption(
              key: const Key('assistantLanguage.radio.bilingual'),
              title: s.onbBilingual,
              subtitle: 'Ответ на языке запроса учителя (RU / KK)',
              value: AssistantLanguage.bilingual,
            ),
            const SizedBox(height: BuilderSpace.lg),
            BuilderButton(
              key: const Key('assistantLanguage.saveBtn'),
              label: 'Применить и создать v$nextVersion',
              loading: _saving,
              onPressed: _applyLanguage,
            ),
            const SizedBox(height: BuilderSpace.xs),
            BuilderButton(
              key: const Key('assistantLanguage.cancelBtn'),
              label: 'Отмена',
              variant: BuilderButtonVariant.secondary,
              onPressed: _saving ? null : () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption({
    required Key key,
    required String title,
    required String subtitle,
    required AssistantLanguage value,
  }) {
    final isSelected = _selectedLanguage == value;
    return InkWell(
      key: key,
      onTap: _saving ? null : () => setState(() => _selectedLanguage = value),
      borderRadius: BorderRadius.circular(BuilderRadii.card),
      child: Container(
        padding: const EdgeInsets.all(BuilderSpace.sm),
        margin: const EdgeInsets.only(bottom: BuilderSpace.xs),
        decoration: BoxDecoration(
          color: isSelected ? BuilderColors.primaryTint : BuilderColors.surface,
          borderRadius: BorderRadius.circular(BuilderRadii.card),
          border: Border.all(
            color: isSelected ? BuilderColors.primary : BuilderColors.line,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected
                  ? BuilderColors.primary
                  : BuilderColors.inkSecondary,
              size: 22,
            ),
            const SizedBox(width: BuilderSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: BuilderType.title),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: BuilderType.small.copyWith(
                      color: BuilderColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
