import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui_kit/controls.dart';
import '../../../ui_kit/identity.dart';
import '../../../ui_kit/tokens.dart';
import '../domain/memory_models.dart';
import 'memory_providers.dart';

/// Screen S42: Long-Term Memory and Classroom Facts (F13-01..F13-08, F13-V01).
class MemoryPage extends ConsumerStatefulWidget {
  final String ownerId;
  final bool isLearnMode;

  const MemoryPage({
    super.key,
    required this.ownerId,
    this.isLearnMode = false,
  });

  @override
  ConsumerState<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends ConsumerState<MemoryPage> {
  final TextEditingController _factInputController = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _factInputController.dispose();
    super.dispose();
  }

  void _handleAddFact() {
    setState(() => _isAdding = true);
  }

  Future<void> _submitNewFact() async {
    final text = _factInputController.text.trim();
    if (text.isEmpty) return;

    final controller = ref.read(memoryControllerProvider(widget.ownerId).notifier);
    await controller.addFact(text);
    _factInputController.clear();
    setState(() => _isAdding = false);
  }

  void _showEditFactDialog(MemoryFact fact) {
    final editController = TextEditingController(text: fact.factText);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: BuilderColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BuilderRadii.sheet),
          ),
          title: Text(
            'Редактировать факт',
            style: BuilderTypography.titleMedium.copyWith(color: BuilderColors.ink),
          ),
          content: TextField(
            controller: editController,
            maxLines: 3,
            maxLength: 300,
            autofocus: true,
            style: BuilderTypography.bodyMedium.copyWith(color: BuilderColors.ink),
            decoration: InputDecoration(
              hintText: 'Введите скорректированный факт...',
              hintStyle: BuilderTypography.bodyMedium.copyWith(color: BuilderColors.inkSecondary),
              filled: true,
              fillColor: BuilderColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BuilderRadii.tile),
                borderSide: const BorderSide(color: BuilderColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BuilderRadii.tile),
                borderSide: const BorderSide(color: BuilderColors.primary, width: 1.5),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
              ),
              child: Text(
                'Отмена',
                style: BuilderTypography.labelMedium.copyWith(color: BuilderColors.inkSecondary),
              ),
            ),
            BuilderButton(
              label: 'Сохранить',
              onPressed: () {
                final newText = editController.text.trim();
                if (newText.isNotEmpty) {
                  ref
                      .read(memoryControllerProvider(widget.ownerId).notifier)
                      .updateFact(fact.id, newText);
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(MemoryFact fact) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: BuilderColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BuilderRadii.sheet),
          ),
          title: Text(
            'Удалить факт?',
            style: BuilderTypography.titleMedium.copyWith(color: BuilderColors.ink),
          ),
          content: Text(
            'Факт «${fact.factText}» будет полностью и безвозвратно удалён с устройства (ADR-02). В последующих запросах модель больше не будет его использовать.',
            style: BuilderTypography.bodyMedium.copyWith(color: BuilderColors.inkSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
              ),
              child: Text(
                'Отмена',
                style: BuilderTypography.labelMedium.copyWith(color: BuilderColors.inkSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                ref
                    .read(memoryControllerProvider(widget.ownerId).notifier)
                    .deleteFact(fact.id);
                Navigator.pop(ctx);
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                foregroundColor: Colors.red.shade700,
              ),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memoryControllerProvider(widget.ownerId));
    final controller = ref.read(memoryControllerProvider(widget.ownerId).notifier);

    return Scaffold(
      backgroundColor: BuilderColors.background,
      appBar: AppBar(
        backgroundColor: BuilderColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.isLearnMode ? 'Уровень 4: Долгая память' : 'Долгая память и факты',
          style: BuilderTypography.titleMedium.copyWith(color: BuilderColors.ink),
        ),
        actions: [
          IconButton(
            key: const Key('memory.refreshBtn'),
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
                  // 1. Privacy Banner (F13-02)
                  Container(
                    key: const Key('memory.privacyBanner'),
                    padding: const EdgeInsets.all(BuilderSpace.sm),
                    decoration: BoxDecoration(
                      color: BuilderColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(BuilderRadii.card),
                      border: Border.all(
                        color: BuilderColors.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: BuilderIcon(
                            BuilderGlyph.info,
                            size: 20,
                            color: BuilderColors.warning,
                          ),
                        ),
                        const SizedBox(width: BuilderSpace.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Защита персональных данных учеников',
                                style: BuilderTypography.labelMedium.copyWith(
                                  color: BuilderColors.warning,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Не сохраняйте персональные данные учеников (ФИО, ИИН, контакты, диагнозы, оценки). '
                                'Факты хранятся на этом телефоне, но передаются модели в составе системного контекста. '
                                'Автоматическое распознавание персональных данных не гарантируется — контроль остаётся за учителем.',
                                style: BuilderTypography.bodySmall.copyWith(
                                  color: BuilderColors.ink,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BuilderSpace.sm),

                  // 2. Explanation Card: Memory vs Conversation History (F13-05)
                  Container(
                    padding: const EdgeInsets.all(BuilderSpace.sm),
                    decoration: BoxDecoration(
                      color: BuilderColors.surface,
                      borderRadius: BorderRadius.circular(BuilderRadii.card),
                      border: Border.all(color: BuilderColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const BuilderIcon(
                              BuilderGlyph.memory,
                              size: 18,
                              color: BuilderColors.primary,
                            ),
                            const SizedBox(width: BuilderSpace.xs),
                            Text(
                              'Память vs История разговора',
                              style: BuilderTypography.labelMedium.copyWith(
                                color: BuilderColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: BuilderSpace.xs),
                        Text(
                          '• История — это реплики текущего диалога, которые сбрасываются при создании нового разговора.\n'
                          '• Память — это проверенные факты (например, количество учеников, длительность урока), которые ассистент использует всегда, даже в новом диалоге.',
                          style: BuilderTypography.bodySmall.copyWith(
                            color: BuilderColors.inkSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BuilderSpace.md),

                  // Error notification if any
                  if (state.errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(BuilderSpace.sm),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(BuilderRadii.tile),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Text(
                        state.errorMessage!,
                        style: BuilderTypography.bodySmall.copyWith(color: Colors.red.shade800),
                      ),
                    ),
                    const SizedBox(height: BuilderSpace.sm),
                  ],

                  // 3. Candidate / Suggested Facts Section (F13-03)
                  if (state.candidateFacts.isNotEmpty) ...[
                    Row(
                      children: [
                        const BuilderIcon(
                          BuilderGlyph.robot,
                          size: 18,
                          color: BuilderColors.primary,
                        ),
                        const SizedBox(width: BuilderSpace.xs),
                        Text(
                          'Предложено моделью (${state.candidateFacts.length})',
                          style: BuilderTypography.titleSmall.copyWith(color: BuilderColors.ink),
                        ),
                      ],
                    ),
                    const SizedBox(height: BuilderSpace.xs),
                    Text(
                      'Модель предлагает запомнить эти факты из ваших разговоров. Они НЕ сохраняются в память без вашего одобрения.',
                      style: BuilderTypography.bodySmall.copyWith(color: BuilderColors.inkSecondary),
                    ),
                    const SizedBox(height: BuilderSpace.xs),
                    ...state.candidateFacts.map((candidate) {
                      return _buildCandidateCard(candidate, controller);
                    }),
                    const SizedBox(height: BuilderSpace.md),
                  ],

                  // 4. Saved Facts Header & Add Button (F13-01)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Сохранённые факты (${state.facts.length})',
                        style: BuilderTypography.titleSmall.copyWith(color: BuilderColors.ink),
                      ),
                      if (!_isAdding)
                        BuilderButton(
                          key: const Key('memory.addFactBtn'),
                          label: '+ Добавить факт',
                          variant: BuilderButtonVariant.secondary,
                          onPressed: _handleAddFact,
                        ),
                    ],
                  ),
                  const SizedBox(height: BuilderSpace.xs),

                  // Inline Add Fact Form
                  if (_isAdding) ...[
                    Container(
                      padding: const EdgeInsets.all(BuilderSpace.sm),
                      decoration: BoxDecoration(
                        color: BuilderColors.surface,
                        borderRadius: BorderRadius.circular(BuilderRadii.card),
                        border: Border.all(color: BuilderColors.primary, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            key: const Key('memory.factInputField'),
                            controller: _factInputController,
                            maxLines: 2,
                            maxLength: 250,
                            autofocus: true,
                            style: BuilderTypography.bodyMedium.copyWith(color: BuilderColors.ink),
                            decoration: InputDecoration(
                              hintText: 'Например: В классе 24 ученика, урок длится 40 минут...',
                              hintStyle: BuilderTypography.bodyMedium.copyWith(color: BuilderColors.inkSecondary),
                              border: InputBorder.none,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                key: const Key('memory.cancelAddBtn'),
                                onPressed: () {
                                  _factInputController.clear();
                                  setState(() => _isAdding = false);
                                },
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(44, 44),
                                ),
                                child: Text(
                                  'Отмена',
                                  style: BuilderTypography.labelMedium.copyWith(color: BuilderColors.inkSecondary),
                                ),
                              ),
                              const SizedBox(width: BuilderSpace.xs),
                              BuilderButton(
                                key: const Key('memory.saveFactBtn'),
                                label: 'Сохранить',
                                loading: state.isSaving,
                                onPressed: _submitNewFact,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: BuilderSpace.sm),
                  ],

                  // Empty State & Educational Presets Loader (F13-07)
                  if (state.facts.isEmpty && !_isAdding) ...[
                    Container(
                      padding: const EdgeInsets.all(BuilderSpace.lg),
                      decoration: BoxDecoration(
                        color: BuilderColors.surface,
                        borderRadius: BorderRadius.circular(BuilderRadii.card),
                        border: Border.all(color: BuilderColors.line),
                      ),
                      child: Column(
                        children: [
                          const BuilderIcon(
                            BuilderGlyph.memory,
                            size: 40,
                            color: BuilderColors.inkSecondary,
                          ),
                          const SizedBox(height: BuilderSpace.xs),
                          Text(
                            'Факты ещё не добавлены',
                            style: BuilderTypography.labelMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: BuilderColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Добавьте факты о вашем классе или загрузите учебные примеры для проверки практики 4 уровня.',
                            textAlign: TextAlign.center,
                            style: BuilderTypography.bodySmall.copyWith(color: BuilderColors.inkSecondary),
                          ),
                          const SizedBox(height: BuilderSpace.md),
                          BuilderButton(
                            key: const Key('memory.loadPresetsBtn'),
                            label: 'Загрузить 3 учебных факта',
                            variant: BuilderButtonVariant.primary,
                            loading: state.isSaving,
                            onPressed: () => controller.loadEducationalPresets(),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // List of Saved Facts
                  ...state.facts.map((fact) {
                    return _buildFactCard(fact, controller);
                  }),

                  const SizedBox(height: BuilderSpace.lg),

                  // Practice Helper Button (if facts are present, allow resetting to 3 presets)
                  if (state.facts.isNotEmpty) ...[
                    Center(
                      child: TextButton.icon(
                        key: const Key('memory.reloadPresetsBtn'),
                        icon: const BuilderIcon(BuilderGlyph.reset, size: 16),
                        label: const Text('Загрузить 3 учебных факта для практики 4 уровня'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          foregroundColor: BuilderColors.primary,
                        ),
                        onPressed: () => controller.loadEducationalPresets(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildCandidateCard(MemoryCandidateFact candidate, MemoryNotifier controller) {
    return Container(
      key: Key('memory.candidate.${candidate.id}'),
      margin: const EdgeInsets.only(bottom: BuilderSpace.xs),
      padding: const EdgeInsets.all(BuilderSpace.sm),
      decoration: BoxDecoration(
        color: BuilderColors.primaryTint,
        borderRadius: BorderRadius.circular(BuilderRadii.tile),
        border: Border.all(color: BuilderColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            candidate.factText,
            style: BuilderTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: BuilderColors.ink,
            ),
          ),
          if (candidate.rationale != null) ...[
            const SizedBox(height: 4),
            Text(
              candidate.rationale!,
              style: BuilderTypography.bodySmall.copyWith(
                color: BuilderColors.inkSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: BuilderSpace.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Min 44x44 touch targets (F13-V01)
              TextButton(
                key: Key('memory.dismissCandidate.${candidate.id}'),
                onPressed: () => controller.dismissSuggested(candidate.id),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: BuilderSpace.sm),
                  foregroundColor: BuilderColors.inkSecondary,
                ),
                child: const Text('Отклонить'),
              ),
              const SizedBox(width: BuilderSpace.xs),
              BuilderButton(
                key: Key('memory.acceptCandidate.${candidate.id}'),
                label: 'Сохранить',
                variant: BuilderButtonVariant.primary,
                onPressed: () => controller.acceptSuggested(candidate.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFactCard(MemoryFact fact, MemoryNotifier controller) {
    return Container(
      key: Key('memory.fact.${fact.id}'),
      margin: const EdgeInsets.only(bottom: BuilderSpace.xs),
      padding: const EdgeInsets.all(BuilderSpace.sm),
      decoration: BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.circular(BuilderRadii.tile),
        border: Border.all(
          color: fact.isEnabled ? BuilderColors.line : BuilderColors.line.withValues(alpha: 0.5),
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
                      fact.factText,
                      style: BuilderTypography.bodyMedium.copyWith(
                        color: fact.isEnabled ? BuilderColors.ink : BuilderColors.inkSecondary,
                        decoration: fact.isEnabled ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: fact.source == MemoryFactSource.suggested
                                ? BuilderColors.primaryTint
                                : BuilderColors.background,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: fact.source == MemoryFactSource.suggested
                                  ? BuilderColors.primary.withValues(alpha: 0.3)
                                  : BuilderColors.line,
                            ),
                          ),
                          child: Text(
                            fact.source.label,
                            style: BuilderTypography.bodySmall.copyWith(
                              fontSize: 11,
                              color: fact.source == MemoryFactSource.suggested
                                  ? BuilderColors.primary
                                  : BuilderColors.inkSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: BuilderSpace.xs),
                        Text(
                          fact.isEnabled ? 'Активен для модели' : 'Выключен',
                          style: BuilderTypography.bodySmall.copyWith(
                            fontSize: 11,
                            color: fact.isEnabled ? Colors.green.shade700 : BuilderColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Switch to toggle active status (F13-01)
              Switch.adaptive(
                key: Key('memory.toggle.${fact.id}'),
                value: fact.isEnabled,
                onChanged: (val) => controller.toggleFact(fact.id, val),
              ),
            ],
          ),

          const SizedBox(height: BuilderSpace.xs),

          // Actions Row with guaranteed 44x44 minimum touch targets (F13-V01)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                key: Key('memory.edit.${fact.id}'),
                icon: const BuilderIcon(BuilderGlyph.settings, size: 18, color: BuilderColors.inkSecondary),
                tooltip: 'Редактировать',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => _showEditFactDialog(fact),
              ),
              IconButton(
                key: Key('memory.delete.${fact.id}'),
                icon: const BuilderIcon(BuilderGlyph.trash, size: 18, color: BuilderColors.inkSecondary),
                tooltip: 'Удалить факт',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => _showDeleteConfirmationDialog(fact),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
