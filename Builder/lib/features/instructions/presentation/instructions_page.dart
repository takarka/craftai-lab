import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ui_kit/ui_kit.dart';
import '../../models/model_providers.dart';
import '../domain/instruction_models.dart';
import '../instructions_providers.dart';

enum SkillScreenMode { work, learn }

class InstructionsPage extends ConsumerStatefulWidget {
  final String ownerId;
  final SkillScreenMode mode;
  final VoidCallback? onPracticeCompleted;

  const InstructionsPage({
    super.key,
    required this.ownerId,
    this.mode = SkillScreenMode.work,
    this.onPracticeCompleted,
  });

  @override
  ConsumerState<InstructionsPage> createState() => _InstructionsPageState();
}

class _InstructionsPageState extends ConsumerState<InstructionsPage> {
  late TextEditingController _testQuestionController;
  late TextEditingController _rawTextController;
  late TextEditingController _reflectionController;

  bool _isPreviewExpanded = true;
  InstructionGroup _selectedGroupFilter = InstructionGroup.role;
  bool _isRawTextFocused = false;

  @override
  void initState() {
    super.initState();
    _testQuestionController = TextEditingController(
      text: 'Объясни, что такое фотосинтез',
    );
    _rawTextController = TextEditingController();
    _reflectionController = TextEditingController();
  }

  @override
  void dispose() {
    _testQuestionController.dispose();
    _rawTextController.dispose();
    _reflectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draftState = ref.watch(instructionDraftProvider(widget.ownerId));
    final draftNotifier = ref.read(
      instructionDraftProvider(widget.ownerId).notifier,
    );
    final selectedCategory = ref.watch(
      selectedCategoryProvider(widget.ownerId),
    );

    // Keep raw text controller in sync if not focused or initially
    if (_rawTextController.text != draftState.config.rawText &&
        !_isRawTextFocused) {
      _rawTextController.text = draftState.config.rawText;
    }

    final isLearnMode = widget.mode == SkillScreenMode.learn;

    return Scaffold(
      backgroundColor: BuilderColors.background,
      appBar: AppBar(
        leading: IconButton(
          key: const Key('instructions.backBtn'),
          icon: const BuilderIcon(BuilderGlyph.back),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: BuilderColors.primaryTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const BuilderIcon(
                BuilderGlyph.doc,
                size: 20,
                color: BuilderColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Инструкции ассистента',
                style: BuilderType.title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (isLearnMode)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: BuilderBadge('Учебный режим', icon: BuilderGlyph.course),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Learn Mode Task Banner (F11-08)
                    if (isLearnMode) ...[
                      _buildLearnTaskBanner(draftState),
                      const SizedBox(height: 16),
                    ],

                    // 2. Character Module Header Card
                    _buildCharacterModuleCard(draftState),
                    const SizedBox(height: 16),

                    // 3. Mode Toggle (Structured Rules vs Raw Mode) (F11-05)
                    _buildModeSelector(draftState, draftNotifier),
                    const SizedBox(height: 16),

                    // 4. Mode-Specific Content
                    if (!draftState.config.isRawMode)
                      _buildStructuredRulesSection(draftState, draftNotifier)
                    else
                      _buildRawTextSection(draftState, draftNotifier),

                    const SizedBox(height: 20),

                    // 5. Instruction Preview & Token Estimation (F11-03)
                    _buildPreviewCard(draftState),
                    const SizedBox(height: 20),

                    // 6. Before / After Test Comparison (F11-06)
                    _buildBeforeAfterTestSection(
                      draftState,
                      draftNotifier,
                      selectedCategory,
                    ),
                    const SizedBox(height: 20),

                    // 7. Reflection Field for Learn Mode (F11-08)
                    if (isLearnMode) ...[
                      _buildReflectionSection(),
                      const SizedBox(height: 20),
                    ],

                    // Disclaimer notice
                    _buildAccuracyDisclaimer(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Fixed Bottom Action Bar (F11-V01)
            _buildBottomActionBar(draftState, draftNotifier),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 1. Learn Task Banner
  // --------------------------------------------------------------------------
  Widget _buildLearnTaskBanner(InstructionDraftState draftState) {
    final rulesMet = draftState.config.enabledRulesCount >= 3;
    final testMet = draftState.testResult != null;
    final reflectionMet = _reflectionController.text.trim().isNotEmpty;

    return Container(
      key: const Key('instructions.learnBanner'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BuilderColors.primaryTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BuilderColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuilderIcon(
                BuilderGlyph.bolt,
                color: BuilderColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Практика уровня 2: Инструкции',
                  style: BuilderType.title.copyWith(
                    color: BuilderColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Настройте поведение вашего ассистента: выберите минимум 3 правила (роль, формат и ограничения), запустите тест «До / после» и сравните ответы.',
            style: BuilderType.small,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTaskCriterion(
                label: '3+ правила (${draftState.config.enabledRulesCount}/3)',
                isDone: rulesMet,
              ),
              _buildTaskCriterion(label: 'Тест запущен', isDone: testMet),
              _buildTaskCriterion(
                label: 'Рефлексия записана',
                isDone: reflectionMet,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCriterion({required String label, required bool isDone}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDone
            ? BuilderColors.primaryTint
            : BuilderColors.surfaceDisabled,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDone ? BuilderColors.primary : BuilderColors.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BuilderIcon(
            isDone ? BuilderGlyph.check : BuilderGlyph.info,
            size: 14,
            color: isDone ? BuilderColors.primary : BuilderColors.inkSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: BuilderType.small.copyWith(
              color: isDone
                  ? BuilderColors.primary
                  : BuilderColors.inkSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 2. Character Module Header Card
  // --------------------------------------------------------------------------
  Widget _buildCharacterModuleCard(InstructionDraftState draftState) {
    return BuilderCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: BuilderColors.primaryTint,
              shape: BoxShape.circle,
              border: Border.all(color: BuilderColors.primary, width: 2),
            ),
            child: const Center(
              child: BuilderIcon(
                BuilderGlyph.robot,
                size: 26,
                color: BuilderColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Модуль инструкций',
                        style: BuilderType.title,
                      ),
                    ),
                    BuilderBadge(
                      '${draftState.config.enabledRulesCount} активных',
                      neutral: draftState.config.enabledRulesCount == 0,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Скрытый текст, предшествующий каждому запросу и направляющий модель',
                  style: BuilderType.small,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 3. Mode Selector (Structured vs Raw)
  // --------------------------------------------------------------------------
  Widget _buildModeSelector(
    InstructionDraftState draftState,
    InstructionDraftNotifier draftNotifier,
  ) {
    final isRaw = draftState.config.isRawMode;
    return Container(
      decoration: BoxDecoration(
        color: BuilderColors.surfaceDisabled,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              key: const Key('instructions.modeSegment.structured'),
              onTap: () => draftNotifier.setMode(isRawMode: false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: !isRaw ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: !isRaw ? BuilderShadows.card : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      BuilderIcon(
                        BuilderGlyph.tool,
                        size: 16,
                        color: !isRaw
                            ? BuilderColors.primary
                            : BuilderColors.inkSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Конструктор правил',
                        style: BuilderType.small.copyWith(
                          color: !isRaw
                              ? BuilderColors.ink
                              : BuilderColors.inkSecondary,
                          fontWeight: !isRaw
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              key: const Key('instructions.modeSegment.raw'),
              onTap: () => draftNotifier.setMode(isRawMode: true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isRaw ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isRaw ? BuilderShadows.card : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      BuilderIcon(
                        BuilderGlyph.doc,
                        size: 16,
                        color: isRaw
                            ? BuilderColors.primary
                            : BuilderColors.inkSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Прямой текст',
                        style: BuilderType.small.copyWith(
                          color: isRaw
                              ? BuilderColors.ink
                              : BuilderColors.inkSecondary,
                          fontWeight: isRaw ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 4A. Structured Rules Section
  // --------------------------------------------------------------------------
  Widget _buildStructuredRulesSection(
    InstructionDraftState draftState,
    InstructionDraftNotifier draftNotifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final group in InstructionGroup.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('instructions.groupFilter.${group.id}'),
                    selected: _selectedGroupFilter == group,
                    label: Text(group.label),
                    avatar: BuilderIcon(
                      group.glyph,
                      size: 16,
                      color: _selectedGroupFilter == group
                          ? BuilderColors.primary
                          : BuilderColors.inkSecondary,
                    ),
                    selectedColor: BuilderColors.primaryTint,
                    backgroundColor: BuilderColors.surfaceDisabled,
                    onSelected: (val) {
                      if (val) setState(() => _selectedGroupFilter = group);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Group Description
        Text(
          _selectedGroupFilter.description,
          style: BuilderType.small.copyWith(color: BuilderColors.inkSecondary),
        ),
        const SizedBox(height: 12),

        // Rules List for selected group
        ...draftState.config.rules
            .where((r) => r.group == _selectedGroupFilter)
            .map((rule) => _buildRuleCard(rule, draftNotifier)),

        // Empty state for custom group
        if (_selectedGroupFilter == InstructionGroup.custom &&
            !draftState.config.rules.any(
              (r) => r.group == InstructionGroup.custom,
            )) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: BuilderColors.surfaceDisabled,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: BuilderColors.line),
            ),
            child: const Center(
              child: Text(
                'Своих правил пока нет. Нажмите кнопку ниже, чтобы добавить.',
                style: BuilderType.body,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Add Custom Rule Button (F11-04)
        SizedBox(
          width: double.infinity,
          child: BuilderButton(
            key: const Key('instructions.addCustomRuleBtn'),
            label: 'Добавить своё правило',
            variant: BuilderButtonVariant.secondary,
            icon: BuilderGlyph.plus,
            onPressed: () => _showAddCustomRuleDialog(context, draftNotifier),
          ),
        ),
      ],
    );
  }

  Widget _buildRuleCard(
    InstructionRule rule,
    InstructionDraftNotifier draftNotifier,
  ) {
    return Container(
      key: Key('instructions.ruleCard.${rule.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: rule.isEnabled
            ? BuilderColors.surface
            : BuilderColors.surfaceDisabled,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: rule.isEnabled ? BuilderColors.primary : BuilderColors.line,
          width: rule.isEnabled ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rule.title,
                  style: BuilderType.title.copyWith(
                    color: rule.isEnabled
                        ? BuilderColors.ink
                        : BuilderColors.inkSecondary,
                  ),
                ),
              ),
              if (rule.isCustom)
                IconButton(
                  key: Key('instructions.deleteRuleBtn.${rule.id}'),
                  icon: const BuilderIcon(
                    BuilderGlyph.trash,
                    size: 18,
                    color: BuilderColors.warning,
                  ),
                  onPressed: () => draftNotifier.deleteCustomRule(rule.id),
                ),
              Switch(
                key: Key('instructions.ruleSwitch.${rule.id}'),
                value: rule.isEnabled,
                onChanged: (val) {
                  draftNotifier.toggleRule(rule.id, val);
                },
                activeTrackColor: BuilderColors.primary,
                activeThumbColor: Colors.white,
              ),
            ],
          ),
          if (rule.explanation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(rule.explanation, style: BuilderType.small),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: BuilderColors.line),
            ),
            child: Text(
              rule.text,
              style: BuilderType.mono.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 4B. Raw Text Section (F11-05)
  // --------------------------------------------------------------------------
  Widget _buildRawTextSection(
    InstructionDraftState draftState,
    InstructionDraftNotifier draftNotifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'Прямое редактирование текста инструкции',
                style: BuilderType.h3,
              ),
            ),
            BuilderBadge('Raw Mode', neutral: true),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Вы можете вручную составить полный текст системного промпта. Сохранение в этом режиме использует введенный текст напрямую, не перезаписывая его конструктором правил.',
          style: BuilderType.small,
        ),
        const SizedBox(height: 12),
        Focus(
          onFocusChange: (hasFocus) {
            setState(() => _isRawTextFocused = hasFocus);
            if (!hasFocus) {
              draftNotifier.updateRawText(_rawTextController.text);
            }
          },
          child: TextField(
            key: const Key('instructions.rawTextField'),
            controller: _rawTextController,
            maxLines: 8,
            style: BuilderType.mono.copyWith(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Введите полный текст инструкции для ассистента...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (val) {
              draftNotifier.updateRawText(val);
            },
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // 5. Instruction Preview & Token Estimation (F11-03)
  // --------------------------------------------------------------------------
  Widget _buildPreviewCard(InstructionDraftState draftState) {
    final activeText = draftState.config.activeInstructionText;
    final tokens = draftState.config.estimatedTokens;
    final isOverLimit = draftState.config.isOverTokenLimit;

    return Container(
      key: const Key('instructions.previewCard'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BuilderColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuilderIcon(
                BuilderGlyph.doc,
                size: 18,
                color: BuilderColors.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Итоговая инструкция (превью)',
                  style: BuilderType.title,
                ),
              ),
              // Token Counter Indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOverLimit
                      ? BuilderColors.warningTint
                      : BuilderColors.surfaceDisabled,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isOverLimit
                        ? BuilderColors.warning
                        : BuilderColors.line,
                  ),
                ),
                child: Text(
                  '~$tokens / 500 токенов',
                  style: BuilderType.small.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isOverLimit
                        ? BuilderColors.warning
                        : BuilderColors.ink,
                  ),
                ),
              ),
              IconButton(
                key: const Key('instructions.previewToggleBtn'),
                icon: BuilderIcon(
                  _isPreviewExpanded
                      ? BuilderGlyph.close
                      : BuilderGlyph.chevron,
                  size: 16,
                ),
                onPressed: () {
                  setState(() => _isPreviewExpanded = !_isPreviewExpanded);
                },
              ),
            ],
          ),
          if (isOverLimit) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: BuilderColors.warningTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  BuilderIcon(
                    BuilderGlyph.info,
                    size: 16,
                    color: BuilderColors.warning,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Инструкция слишком длинная: модель может пропускать правила в процессе диалога.',
                      style: TextStyle(
                        fontSize: 12,
                        color: BuilderColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_isPreviewExpanded) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BuilderColors.line),
              ),
              child: SelectableText(
                activeText.isNotEmpty
                    ? activeText
                    : '(Инструкция пуста: включите правила или добавьте текст)',
                style: BuilderType.mono.copyWith(
                  fontSize: 12,
                  color: activeText.isNotEmpty
                      ? BuilderColors.ink
                      : BuilderColors.inkSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 6. Before / After Test Comparison (F11-06)
  // --------------------------------------------------------------------------
  Widget _buildBeforeAfterTestSection(
    InstructionDraftState draftState,
    InstructionDraftNotifier draftNotifier,
    dynamic selectedCategory,
  ) {
    return BuilderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuilderIcon(
                BuilderGlyph.search,
                size: 20,
                color: BuilderColors.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Проверка «До / После»', style: BuilderType.h3),
              ),
              BuilderBadge('Модель: ${selectedCategory.id}', neutral: true),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Задайте вопрос, чтобы увидеть разницу в ответе ассистента до и после добавления инструкций на одной и той же модели.',
            style: BuilderType.small,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('instructions.testQuestionField'),
            controller: _testQuestionController,
            decoration: const InputDecoration(
              labelText: 'Тестовый вопрос',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: BuilderButton(
              key: const Key('instructions.testBeforeAfterBtn'),
              label: draftState.isTesting
                  ? 'Выполняется проверка...'
                  : 'Проверить ответ (До / После)',
              icon: BuilderGlyph.bolt,
              variant: BuilderButtonVariant.primary,
              loading: draftState.isTesting,
              onPressed: draftState.isTesting
                  ? null
                  : () async {
                      final question = _testQuestionController.text.trim();
                      if (question.isEmpty) return;

                      try {
                        await draftNotifier.runBeforeAfterTest(
                          question: question,
                          category: selectedCategory,
                        );
                      } catch (_) {
                        // The provider exposes the error below the test button.
                      }
                    },
            ),
          ),

          if (draftState.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              draftState.errorMessage!,
              key: const Key('instructions.testError'),
              style: BuilderType.small.copyWith(color: BuilderColors.warning),
            ),
          ],

          // Test Comparison Results
          if (draftState.testResult != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Результаты сравнения:', style: BuilderType.title),
            const SizedBox(height: 10),

            // Before Card
            Container(
              key: const Key('instructions.beforeCard'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BuilderColors.surfaceDisabled,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BuilderColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BuilderBadge('До (без инструкций)', neutral: true),
                      Text(
                        'Трасса: ${draftState.testResult!.beforeTrace.requestId.split('').take(18).join()}...',
                        style: BuilderType.mono.copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    draftState.testResult!.beforeAnswer,
                    style: BuilderType.body,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // After Card
            Container(
              key: const Key('instructions.afterCard'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BuilderColors.primaryTint,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BuilderColors.primary),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BuilderBadge(
                        'После (с инструкциями)',
                        icon: BuilderGlyph.check,
                      ),
                      Text(
                        'Трасса: ${draftState.testResult!.afterTrace.requestId.split('').take(18).join()}...',
                        style: BuilderType.mono.copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    draftState.testResult!.afterAnswer,
                    style: BuilderType.body.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 7. Reflection Field for Learn Mode (F11-08)
  // --------------------------------------------------------------------------
  Widget _buildReflectionSection() {
    return BuilderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              BuilderIcon(
                BuilderGlyph.info,
                size: 18,
                color: BuilderColors.primary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text('Рефлексия учителя', style: BuilderType.title),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Опишите в 1-2 предложениях: как изменился ответ ассистента? Повлияли ли правила на структуру и тон?',
            style: BuilderType.small,
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('instructions.reflectionInput'),
            controller: _reflectionController,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText:
                  'Например: Ответ стал кратким, структурированным по пунктам и в роли помощника учителя биологии.',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  List<String> _missingPracticeRequirements(InstructionDraftState draftState) {
    return [
      if (draftState.config.enabledRulesCount < 3)
        'выберите минимум 3 правила (сейчас ${draftState.config.enabledRulesCount})',
      if (draftState.testResult == null) 'запустите тест «До / после»',
      if (_reflectionController.text.trim().isEmpty) 'напишите рефлексию',
    ];
  }

  // --------------------------------------------------------------------------
  // Accuracy Disclaimer (F11-03)
  // --------------------------------------------------------------------------
  Widget _buildAccuracyDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BuilderColors.surfaceDisabled,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BuilderColors.line),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BuilderIcon(
            BuilderGlyph.info,
            size: 18,
            color: BuilderColors.inkSecondary,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Важно: инструкции определяют роль и формат ответа, но не гарантируют 100% фактическую точность модели. Для работы с фактами подключаются модули «Знания (RAG)» и «Память».',
              style: TextStyle(fontSize: 12, color: BuilderColors.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Fixed Bottom Action Bar (F11-V01)
  // --------------------------------------------------------------------------
  Widget _buildBottomActionBar(
    InstructionDraftState draftState,
    InstructionDraftNotifier draftNotifier,
  ) {
    final isLearnMode = widget.mode == SkillScreenMode.learn;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: BuilderColors.line)),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            offset: Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: BuilderButton(
              key: const Key('instructions.saveBtn'),
              label: draftState.isSaving
                  ? 'Сохранение...'
                  : (isLearnMode
                        ? 'Завершить практику и сохранить'
                        : 'Сохранить инструкции'),
              icon: BuilderGlyph.check,
              loading: draftState.isSaving,
              onPressed: draftState.isSaving
                  ? null
                  : () async {
                      final currentDraft = ref.read(
                        instructionDraftProvider(widget.ownerId),
                      );
                      final missing = _missingPracticeRequirements(
                        currentDraft,
                      );
                      if (isLearnMode && missing.isNotEmpty) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                'Для завершения практики ${missing.join(', ')}.',
                              ),
                            ),
                          );
                        return;
                      }

                      await draftNotifier.saveToAssistant();

                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Инструкции сохранены. Создана новая версия ассистента.',
                          ),
                        ),
                      );

                      if (isLearnMode) {
                        widget.onPracticeCompleted?.call();
                      } else {
                        context.pop();
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Dialog: Add Custom Rule (F11-04)
  // --------------------------------------------------------------------------
  void _showAddCustomRuleDialog(
    BuildContext context,
    InstructionDraftNotifier draftNotifier,
  ) {
    final titleController = TextEditingController();
    final textController = TextEditingController();
    final explanationController = TextEditingController();
    var selectedGroup = InstructionGroup.role;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              key: const Key('instructions.addCustomRuleDialog'),
              title: const Text('Новое правило', style: BuilderType.title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Группа правила:', style: BuilderType.small),
                    const SizedBox(height: 6),
                    DropdownButton<InstructionGroup>(
                      value: selectedGroup,
                      isExpanded: true,
                      items: InstructionGroup.values.map((g) {
                        return DropdownMenuItem(value: g, child: Text(g.label));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedGroup = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Название правила',
                        hintText: 'Например: Задачи по химии 8 класса',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: textController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Текст правила (для модели)',
                        hintText:
                            'Ты объясняешь химические реакции с формулами...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: explanationController,
                      decoration: const InputDecoration(
                        labelText: 'Пояснение (для учителя)',
                        hintText: 'Задаёт предметную специфику химии',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  key: const Key('instructions.confirmAddRuleBtn'),
                  onPressed: () {
                    final title = titleController.text.trim();
                    final text = textController.text.trim();
                    if (title.isEmpty || text.isEmpty) return;

                    draftNotifier.addCustomRule(
                      group: selectedGroup,
                      title: title,
                      text: text,
                      explanation: explanationController.text.trim(),
                    );
                    Navigator.of(dialogCtx).pop();
                  },
                  child: const Text('Добавить'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
