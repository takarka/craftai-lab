import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui_kit/identity.dart';
import '../../../ui_kit/tokens.dart';
import '../domain/tool_definition.dart';
import 'd07_os_permission_dialog.dart';
import 'tool_confirmation_card.dart';
import 'tools_providers.dart';

/// Screen S43: Assistant Tools Management (F14-02, F14-04, F14-09, F14-13).
class ToolsPage extends ConsumerStatefulWidget {
  final String ownerId;
  final bool isLearnMode;

  const ToolsPage({
    super.key,
    required this.ownerId,
    this.isLearnMode = false,
  });

  @override
  ConsumerState<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends ConsumerState<ToolsPage> {
  void _openOsPermissionDialog(ToolItemState item) {
    final tool = item.definition;
    final isDenied = item.osPermission == OsPermissionStatus.denied;

    D07OsPermissionDialog.show(
      context,
      tool: tool,
      isDenied: isDenied,
    ).then((proceed) {
      if (proceed == true) {
        // Simulated OS grant
        ref
            .read(toolsControllerProvider(widget.ownerId).notifier)
            .setOsPermission(tool.name, OsPermissionStatus.granted);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(toolsControllerProvider(widget.ownerId));
    final controller = ref.read(toolsControllerProvider(widget.ownerId).notifier);

    return Scaffold(
      backgroundColor: BuilderColors.background,
      appBar: AppBar(
        backgroundColor: BuilderColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.isLearnMode ? 'Уровень 5: Инструменты' : 'Инструменты ассистента',
          style: BuilderTypography.titleMedium.copyWith(color: BuilderColors.ink),
        ),
        actions: [
          IconButton(
            key: const Key('tools.refreshBtn'),
            icon: const BuilderIcon(BuilderGlyph.reset, size: 20),
            tooltip: 'Обновить',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => controller.load(),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => controller.load(),
              child: ListView(
                padding: const EdgeInsets.all(BuilderSpace.md),
                children: [
                  // 1. Pending Confirmations Section (if any exist) (F14-05)
                  if (state.pendingActions.isNotEmpty) ...[
                    Row(
                      children: [
                        const BuilderIcon(
                          BuilderGlyph.bolt,
                          size: 20,
                          color: BuilderColors.primary,
                        ),
                        const SizedBox(width: BuilderSpace.xs),
                        Text(
                          'Ожидают подтверждения (${state.pendingActions.length})',
                          style: BuilderTypography.titleSmall.copyWith(color: BuilderColors.ink),
                        ),
                      ],
                    ),
                    const SizedBox(height: BuilderSpace.xs),
                    ...state.pendingActions.map((action) {
                      return ToolConfirmationCard(
                        action: action,
                        onConfirm: (id) => controller.confirmAction(id),
                        onReject: (id) => controller.rejectAction(id),
                      );
                    }),
                    const SizedBox(height: BuilderSpace.md),
                  ],

                  // 2. Info / Safety Banner (F14-05, F14-08)
                  Container(
                    key: const Key('tools.safetyBanner'),
                    padding: const EdgeInsets.all(BuilderSpace.sm),
                    decoration: BoxDecoration(
                      color: BuilderColors.surface,
                      borderRadius: BorderRadius.circular(BuilderRadii.card),
                      border: Border.all(color: BuilderColors.line),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: BuilderIcon(
                            BuilderGlyph.info,
                            size: 20,
                            color: BuilderColors.primary,
                          ),
                        ),
                        const SizedBox(width: BuilderSpace.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Контроль и безопасность действий',
                                style: BuilderTypography.labelMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: BuilderColors.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Любые действия, изменяющие данные (создание уроков, удаление заметок, звонки), '
                                'всегда требуют вашего явного подтверждения в диалоге. '
                                'Ассистент никогда не звонит и не отправляет сообщения автоматически.',
                                style: BuilderTypography.bodySmall.copyWith(
                                  color: BuilderColors.inkSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BuilderSpace.md),

                  // 3. Three Tool Groups (F14-02)
                  _buildGroupSection(
                    title: '1 · Календарь и расписание',
                    category: ToolCategory.calendar,
                    items: state.toolItems.where((i) => i.definition.category == ToolCategory.calendar).toList(),
                    controller: controller,
                  ),
                  const SizedBox(height: BuilderSpace.md),

                  _buildGroupSection(
                    title: '2 · Личные заметки и черновики',
                    category: ToolCategory.notes,
                    items: state.toolItems.where((i) => i.definition.category == ToolCategory.notes).toList(),
                    controller: controller,
                  ),
                  const SizedBox(height: BuilderSpace.md),

                  _buildGroupSection(
                    title: '3 · Связь и поиск',
                    category: ToolCategory.communication,
                    items: state.toolItems.where((i) => i.definition.category == ToolCategory.communication || i.definition.category == ToolCategory.search).toList(),
                    controller: controller,
                    disclosure: Container(
                      key: const Key('tools.webSearchDisclosure'),
                      margin: const EdgeInsets.only(top: BuilderSpace.xs),
                      padding: const EdgeInsets.all(BuilderSpace.sm),
                      decoration: BoxDecoration(
                        color: BuilderColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(BuilderRadii.tile),
                        border: Border.all(color: BuilderColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: BuilderIcon(BuilderGlyph.cloud, size: 16, color: BuilderColors.warning),
                          ),
                          const SizedBox(width: BuilderSpace.xs),
                          Expanded(
                            child: Text(
                              'Поиск в интернете передаёт поисковый запрос внешнему серверу CraftAI Search. '
                              'По умолчанию отключён. Не отправляйте персональные данные учеников в поисковых запросах.',
                              style: BuilderTypography.bodySmall.copyWith(color: BuilderColors.ink, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: BuilderSpace.md),

                  // 4. Practice Verification Card (F14-13)
                  Container(
                    key: const Key('tools.practiceCard'),
                    padding: const EdgeInsets.all(BuilderSpace.sm),
                    decoration: BoxDecoration(
                      color: BuilderColors.surface,
                      borderRadius: BorderRadius.circular(BuilderRadii.card),
                      border: Border.all(color: BuilderColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Учебная проверка подтверждения',
                          style: BuilderTypography.titleSmall.copyWith(
                            color: BuilderColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Проверьте появление карточки подтверждения действия перед записью в календарь.',
                          style: BuilderTypography.bodySmall.copyWith(color: BuilderColors.inkSecondary),
                        ),
                        const SizedBox(height: BuilderSpace.sm),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            key: const Key('tools.createTestEventBtn'),
                            icon: const BuilderIcon(BuilderGlyph.calendar, size: 18),
                            label: const Text('Создать тестовое событие расписания'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 44),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onPressed: () => controller.createEducationalTestAction(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: BuilderSpace.lg),
                ],
              ),
            ),
    );
  }

  Widget _buildGroupSection({
    required String title,
    required ToolCategory category,
    required List<ToolItemState> items,
    required ToolsNotifier controller,
    Widget? disclosure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: BuilderTypography.titleSmall.copyWith(
            color: BuilderColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: BuilderSpace.xs),
        ...items.map((item) => _buildToolItemCard(item, controller)),
        if (disclosure != null) disclosure,
      ],
    );
  }

  Widget _buildToolItemCard(ToolItemState item, ToolsNotifier controller) {
    final def = item.definition;

    return Container(
      key: Key('tool.card.${def.name}'),
      margin: const EdgeInsets.only(bottom: BuilderSpace.xs),
      padding: const EdgeInsets.all(BuilderSpace.sm),
      decoration: BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.circular(BuilderRadii.tile),
        border: Border.all(
          color: item.isEnabled ? BuilderColors.line : BuilderColors.line.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      def.displayName,
                      style: BuilderTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: item.isEnabled ? BuilderColors.ink : BuilderColors.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      def.description,
                      style: BuilderTypography.bodySmall.copyWith(
                        color: BuilderColors.inkSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Tool grant switch (F14-02)
              Switch.adaptive(
                key: Key('tool.switch.${def.name}'),
                value: item.isEnabled,
                onChanged: (val) => controller.toggleGrant(def.name, val),
              ),
            ],
          ),
          const SizedBox(height: BuilderSpace.xs),

          // Badges and OS Permission row
          Row(
            children: [
              // Capability badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: def.requiresConfirmation
                      ? BuilderColors.primaryTint
                      : BuilderColors.background,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  def.requiresConfirmation ? 'Требует подтверждения' : 'Чтение',
                  style: BuilderTypography.bodySmall.copyWith(
                    fontSize: 11,
                    color: def.requiresConfirmation ? BuilderColors.primary : BuilderColors.inkSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: BuilderSpace.xs),

              // OS Permission Chip (if tool requires OS permission)
              if (def.defaultOsPermission != OsPermissionStatus.notRequired) ...[
                InkWell(
                  key: Key('tool.osPermBtn.${def.name}'),
                  onTap: () => _openOsPermissionDialog(item),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.osPermission == OsPermissionStatus.granted
                          ? Colors.green.shade50
                          : (item.osPermission == OsPermissionStatus.denied
                              ? Colors.red.shade50
                              : BuilderColors.background),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: item.osPermission == OsPermissionStatus.granted
                            ? Colors.green.shade200
                            : (item.osPermission == OsPermissionStatus.denied
                                ? Colors.red.shade200
                                : BuilderColors.line),
                      ),
                    ),
                    child: Text(
                      item.osPermission.label,
                      style: BuilderTypography.bodySmall.copyWith(
                        fontSize: 11,
                        color: item.osPermission == OsPermissionStatus.granted
                            ? Colors.green.shade800
                            : (item.osPermission == OsPermissionStatus.denied
                                ? Colors.red.shade800
                                : BuilderColors.inkSecondary),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
