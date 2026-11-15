import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../domain/model_catalog.dart';
import '../model_providers.dart';

class ModelSelectionPage extends ConsumerWidget {
  const ModelSelectionPage({super.key, required this.ownerId});

  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context);
    final catalogAsync = ref.watch(modelCatalogFutureProvider);

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
                style: BuilderType.body.copyWith(
                  color: BuilderColors.inkSecondary,
                ),
              ),
              const SizedBox(height: 12),

              // Data transfer badge (D02 correlation)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: BuilderColors.warningTint,
                      borderRadius: BorderRadius.circular(BuilderRadii.chip),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BuilderIcon(
                          BuilderGlyph.globe,
                          size: 14,
                          color: BuilderColors.warning,
                        ),
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
                    const BuilderIcon(
                      BuilderGlyph.info,
                      size: 18,
                      color: BuilderColors.inkSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.modelsDisclaimer,
                        style: BuilderType.small.copyWith(
                          color: BuilderColors.inkSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Models list
              for (final descriptor in catalog.models) ...[
                _ModelCard(
                  key: Key('models.card.${descriptor.modelId}'),
                  descriptor: descriptor,
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

class _ModelCard extends StatelessWidget {
  const _ModelCard({super.key, required this.descriptor});

  final ModelDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);

    return BuilderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  descriptor.modelId,
                  style: BuilderType.h3.copyWith(color: BuilderColors.ink),
                ),
              ),
              if (!descriptor.available)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
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
                ),
            ],
          ),
        ],
      ),
    );
  }
}
