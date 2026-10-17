import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../domain/model_catalog.dart';
import '../domain/model_category.dart';
import '../model_providers.dart';

class ModelSelectionPage extends ConsumerWidget {
  const ModelSelectionPage({super.key, required this.ownerId});

  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context);
    final catalogAsync = ref.watch(modelCatalogFutureProvider);
    final currentSelected = ref.watch(selectedCategoryProvider(ownerId));

    final catalog = catalogAsync.asData?.value ?? ModelCatalog.defaultCatalog();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.modelsTitle),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header description
              Text(
                s.modelsSubtitle,
                style: BuilderType.body.copyWith(color: BuilderColors.inkSecondary),
              ),
              const SizedBox(height: 12),

              // Data transfer badge (D02 correlation)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: BuilderColors.warningTint,
                      borderRadius: BorderRadius.circular(BuilderRadii.chip),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BuilderIcon(BuilderGlyph.globe, size: 14, color: BuilderColors.warning),
                        const SizedBox(width: 4),
                        Text(
                          s.modelsDataNotice,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: BuilderColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Disclaimer banner (F06-05)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BuilderColors.background,
                  borderRadius: BorderRadius.circular(BuilderRadii.card),
                  border: Border.all(color: BuilderColors.lineDisabled),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BuilderIcon(BuilderGlyph.info, size: 18, color: BuilderColors.inkSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.modelsDisclaimer,
                        style: BuilderType.small.copyWith(color: BuilderColors.inkSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Unavailable alert if the currently selected category is down (F06-07)
              if (!catalog.isCategoryAvailable(currentSelected)) ...[
                Container(
                  key: const Key('models.unavailableAlert'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: BuilderColors.warningTint,
                    borderRadius: BorderRadius.circular(BuilderRadii.card),
                    border: Border.all(color: BuilderColors.warning),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.modelsUnavailableWarning,
                        style: BuilderType.body.copyWith(
                          color: BuilderColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      BuilderButton(
                        key: const Key('models.switchToRecommended'),
                        label: '${s.modelsStandardTitle} (${s.modelsRecommended})',
                        variant: BuilderButtonVariant.secondary,
                        onPressed: () {
                          final alternative = catalog.suggestAlternative(currentSelected);
                          ref.read(selectedCategoryProvider(ownerId).notifier).select(alternative);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 3 Category Cards (S33)
              for (final category in ModelCategory.values) ...[
                _ModelCategoryCard(
                  key: Key('models.card.${category.id}'),
                  category: category,
                  isSelected: currentSelected == category,
                  descriptor: catalog.getModel(category),
                  onSelect: () {
                    ref.read(selectedCategoryProvider(ownerId).notifier).select(category);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelCategoryCard extends StatelessWidget {
  const _ModelCategoryCard({
    super.key,
    required this.category,
    required this.isSelected,
    required this.descriptor,
    required this.onSelect,
  });

  final ModelCategory category;
  final bool isSelected;
  final ModelDescriptor descriptor;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);

    final title = switch (category) {
      ModelCategory.fast => s.modelsFastTitle,
      ModelCategory.standard => s.modelsStandardTitle,
      ModelCategory.advanced => s.modelsAdvancedTitle,
    };

    final description = switch (category) {
      ModelCategory.fast => s.modelsFastDesc,
      ModelCategory.standard => s.modelsStandardDesc,
      ModelCategory.advanced => s.modelsAdvancedDesc,
    };

    return BuilderCard(
      selected: isSelected,
      onTap: onSelect,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row with category title, recommended chip & availability badge
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      title,
                      style: BuilderType.h3.copyWith(
                        color: isSelected ? BuilderColors.primary : BuilderColors.ink,
                      ),
                    ),
                    if (category == ModelCategory.standard) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: BuilderColors.primaryTint,
                          borderRadius: BorderRadius.circular(BuilderRadii.chip),
                        ),
                        child: Text(
                          s.modelsRecommended,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: BuilderColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!descriptor.available)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: BuilderColors.warningTint,
                    borderRadius: BorderRadius.circular(BuilderRadii.chip),
                  ),
                  child: Text(
                    s.modelsUnavailableBadge,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: BuilderColors.warning,
                    ),
                  ),
                )
              else if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: BuilderColors.primary,
                  size: 22,
                )
              else
                const Icon(
                  Icons.radio_button_unchecked,
                  color: BuilderColors.lineDisabled,
                  size: 22,
                ),
            ],
          ),
          const SizedBox(height: 6),

          Text(
            description,
            style: BuilderType.body.copyWith(
              color: BuilderColors.inkSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),

          // 3-segment relative scales (F06-V01): Quality, Speed, Price
          _ScaleRow(
            label: s.modelsQuality,
            value: category.qualityRating,
          ),
          const SizedBox(height: 8),
          _ScaleRow(
            label: s.modelsSpeed,
            value: category.speedRating,
          ),
          const SizedBox(height: 8),
          _ScaleRow(
            label: s.modelsPrice,
            value: category.priceRating,
          ),
        ],
      ),
    );
  }
}

class _ScaleRow extends StatelessWidget {
  const _ScaleRow({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: BuilderType.small.copyWith(
              color: BuilderColors.inkSecondary,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: BuilderProgress(
            completed: value,
            total: 3,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$value/3',
          style: BuilderType.small.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 11,
            color: BuilderColors.inkSecondary,
          ),
        ),
      ],
    );
  }
}
