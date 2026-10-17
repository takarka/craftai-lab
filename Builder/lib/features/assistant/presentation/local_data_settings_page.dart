import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../assistant_providers.dart';
import 'reset_confirmation_dialog.dart';

class LocalDataSettingsPage extends ConsumerWidget {
  const LocalDataSettingsPage({super.key, required this.ownerId});

  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppLocalizations.of(context);
    final summaryAsync = ref.watch(localDataSummaryProvider(ownerId));
    final retentionAsync = ref.watch(storageRetentionDaysProvider(ownerId));
    final retentionDays = retentionAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.localDataTitle, style: BuilderType.h3),
        leading: IconButton(
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
              // Device storage warning notice (F09-09)
              BuilderNotice(
                title: 'Локальное хранилище',
                body: s.localDataDeviceWarning,
                warning: true,
              ),
              const SizedBox(height: 20),

              // Data map (F09-09)
              Text(s.localDataMapHeader, style: BuilderType.h3),
              const SizedBox(height: 12),
              summaryAsync.when(
                loading: () => const BuilderSkeleton(),
                error: (e, _) => Text('Ошибка: $e'),
                data: (data) => BuilderCard(
                  child: Column(
                    children: [
                      _DataRow(
                        icon: Icons.chat_bubble_outline,
                        title: s.localDataConversations(data.conversationsCount),
                        subtitle: '${data.messagesCount} сообщений',
                      ),
                      const Divider(height: 16),
                      _DataRow(
                        icon: Icons.psychology_outlined,
                        title: s.localDataMemoryFacts(data.memoryFactsCount),
                      ),
                      const Divider(height: 16),
                      _DataRow(
                        icon: Icons.folder_open_outlined,
                        title: s.localDataDocuments(data.documentsCount),
                        subtitle: '${data.chunksCount} фрагментов в индексе',
                      ),
                      const Divider(height: 16),
                      _DataRow(
                        icon: Icons.insights_outlined,
                        title: s.localDataTraces(data.tracesCount),
                      ),
                      const Divider(height: 16),
                      _DataRow(
                        icon: Icons.history,
                        title: s.localDataVersions(data.versionsCount),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Retention policy selector (F09-09 / F09-V02)
              Text(s.localDataRetentionHeader, style: BuilderType.h3),
              const SizedBox(height: 6),
              Text(
                s.localDataRetentionSubtitle,
                style: BuilderType.body.copyWith(color: BuilderColors.inkSecondary),
              ),
              const SizedBox(height: 12),
              BuilderSegments<int?>(
                key: const Key('localData.retentionSegments'),
                options: [
                  (30, s.localDataRetention30Days),
                  (90, s.localDataRetention90Days),
                  (null, s.localDataRetentionForever),
                ],
                value: retentionDays,
                onChanged: (days) {
                  ref.read(assistantControllerProvider(ownerId)).setRetentionDays(days);
                },
              ),
              const SizedBox(height: 32),

              // Reset action button (F09-09, F09-10, F09-11)
              Text('Сброс ассистента', style: BuilderType.h3),
              const SizedBox(height: 6),
              Text(
                'Полная очистка локальных материалов с возвратом к начальной настройке.',
                style: BuilderType.small.copyWith(color: BuilderColors.inkSecondary),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: BuilderButton(
                  key: const Key('localData.resetBtn'),
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
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: BuilderColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: BuilderType.title),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: BuilderType.small.copyWith(color: BuilderColors.inkSecondary)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
