import 'package:flutter/material.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';

class D02ConsentSheet extends StatelessWidget {
  const D02ConsentSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 600;

    final content = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(BuilderRadii.sheet),
          topRight: const Radius.circular(BuilderRadii.sheet),
          bottomLeft: isDesktop
              ? const Radius.circular(BuilderRadii.sheet)
              : Radius.zero,
          bottomRight: isDesktop
              ? const Radius.circular(BuilderRadii.sheet)
              : Radius.zero,
        ),
        boxShadow: BuilderShadows.sheet,
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: BuilderColors.lineDisabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Globe icon tile
              const Align(
                alignment: Alignment.centerLeft,
                child: BuilderIconTile(
                  BuilderGlyph.globe,
                  warm: true,
                  size: 48,
                ),
              ),
              const SizedBox(height: 14),

              // Title
              Text(s.d02Title, style: BuilderType.h1),
              const SizedBox(height: 10),

              // Subtitle
              Text(
                s.d02Subtitle,
                style: const TextStyle(
                  color: BuilderColors.inkSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),

              // Data transfer chain: Phone -> CraftAI -> Model
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  _ChainChip(
                    icon: BuilderGlyph.phone,
                    label: s.d02StepPhone,
                    warm: false,
                  ),
                  const Icon(
                    Icons.arrow_forward,
                    size: 14,
                    color: BuilderColors.inkSecondary,
                  ),
                  _ChainChip(
                    icon: BuilderGlyph.cloud,
                    label: s.d02StepCraftAi,
                    warm: false,
                  ),
                  const Icon(
                    Icons.arrow_forward,
                    size: 14,
                    color: BuilderColors.inkSecondary,
                  ),
                  _ChainChip(
                    icon: BuilderGlyph.robot,
                    label: s.d02StepModel,
                    warm: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Warning banner: Do not send student data
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: BuilderColors.accent, width: 1.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: BuilderColors.warning,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.d02Warning,
                        style: const TextStyle(
                          fontSize: 14,
                          color: BuilderColors.ink,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Primary action: Understand ("Понятно")
              BuilderButton(
                key: const Key('d02.understand'),
                label: s.d02Understand,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 10),

              // Secondary action: Not now ("Не сейчас")
              BuilderButton(
                key: const Key('d02.notNow'),
                label: s.d02NotNow,
                variant: BuilderButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );

    if (isDesktop) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(color: Colors.transparent, child: content),
        ),
      );
    }

    return content;
  }
}

class _ChainChip extends StatelessWidget {
  const _ChainChip({
    required this.icon,
    required this.label,
    required this.warm,
  });

  final BuilderGlyph icon;
  final String label;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: warm ? BuilderColors.warningTint : BuilderColors.primaryTint,
        borderRadius: BorderRadius.circular(BuilderRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BuilderIcon(
            icon,
            size: 14,
            color: warm ? BuilderColors.warning : BuilderColors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: warm ? BuilderColors.warning : BuilderColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool?> showD02ConsentSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const D02ConsentSheet(),
  );
}
