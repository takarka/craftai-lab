import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../../chat/chat_providers.dart';
import '../../chat/domain/chat_message.dart';
import '../../chat/presentation/conversation_history_sheet.dart';
import '../../chat/presentation/markdown_message_view.dart';

import '../../models/domain/model_category.dart';
import '../../models/model_providers.dart';
import '../../onboarding/presentation/d02_consent_sheet.dart';
import '../../policy/policy_providers.dart';
import '../../trace/presentation/trace_sheet.dart';
import '../../course/course_providers.dart';
import '../../course/domain/course_catalog.dart';
import '../../skills/domain/skill_scenario.dart';
import '../../skills/domain/skill_preparation.dart';
import '../../skills/skills_providers.dart';
import '../../skills/presentation/skill_picker_sheet.dart';
import '../../skills/presentation/skill_request_summary.dart';

class SkillRunDraft {
  SkillRunDraft({required this.skill, required Map<String, String> inputs})
    : inputs = Map.unmodifiable(inputs);
  final SkillScenario skill;
  final Map<String, String> inputs;
}

class AssistantChatPage extends ConsumerStatefulWidget {
  const AssistantChatPage({super.key, required this.ownerId, this.skillRun});

  final String ownerId;
  final SkillRunDraft? skillRun;

  @override
  ConsumerState<AssistantChatPage> createState() => _AssistantChatPageState();
}

class _AssistantChatPageState extends ConsumerState<AssistantChatPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  late SkillRunDraft? _run = widget.skillRun;
  bool _skillSent = false;
  bool _skillSending = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottomIfNeeded() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 100) {
      _scrollController.jumpTo(maxScroll);
    }
  }

  Future<bool> _handleSend([
    String? presetText,
    SkillRunDraft? skillDraft,
  ]) async {
    final text = presetText ?? _textController.text.trim();
    if (text.isEmpty) return false;

    final policyRepo = ref.read(policyRepositoryProvider);
    final ack = await policyRepo.isPolicyAcknowledged(
      ownerId: widget.ownerId,
      policyId: 'd02_cross_border_transfer',
    );

    if (!ack) {
      if (!mounted) return false;
      final consentGiven = await showD02ConsentSheet(context);
      if (consentGiven == true) {
        await policyRepo.acknowledgePolicy(
          ownerId: widget.ownerId,
          policyId: 'd02_cross_border_transfer',
          policyVersion: 'v1.0',
        );
      } else {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Для обращения к облачной модели требуется согласие D02.',
            ),
          ),
        );
        return false;
      }
    }

    if (!mounted) return false;
    if (skillDraft != null) {
      final repository = ref.read(skillsRepositoryProvider);
      final current = await repository?.getSkills(widget.ownerId);
      if (!mounted) return false;
      if (current == null ||
          !current.any(
            (skill) =>
                skill.id == skillDraft.skill.id &&
                skill.toJson().toString() ==
                    skillDraft.skill.toJson().toString(),
          )) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localizations.localeOf(context).languageCode == 'kk'
                  ? 'Дағды өзгертілген немесе жойылған. Оны тізімнен қайта ашыңыз.'
                  : 'Навык изменён или удалён. Откройте его заново из списка.',
            ),
          ),
        );
        return false;
      }
    }
    final state = ref.read(chatSessionProvider(widget.ownerId));
    if (state.isLoading ||
        state.isGenerating ||
        state.activeConversation == null) {
      return false;
    }
    if (presetText == null) {
      _textController.clear();
    }
    await ref
        .read(chatSessionProvider(widget.ownerId).notifier)
        .sendMessage(text);
    return true;
  }

  Future<void> _pickSkill() async {
    final picked = await showSkillPickerSheet(
      context,
      ownerId: widget.ownerId,
      onOpenSkills: () => context.push('/assistant/skills'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _run = SkillRunDraft(skill: picked.skill, inputs: picked.inputs);
      _skillSent = false;
    });
  }

  Future<void> _sendSkill() async {
    final draft = _run;
    if (draft == null || _skillSending || _skillSent) return;
    setState(() => _skillSending = true);
    try {
      final prepared = SkillPreparation.prepare(draft.skill, draft.inputs);
      if (!prepared.isReady) return;
      final sent = await _handleSend(prepared.userPrompt, draft);
      if (mounted && sent) setState(() => _skillSent = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localizations.localeOf(context).languageCode == 'kk'
                  ? 'Жіберілмеді. Қайталап көріңіз.'
                  : 'Не удалось отправить. Попробуйте ещё раз.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _skillSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final chatState = ref.watch(chatSessionProvider(widget.ownerId));
    final selectedCategory = ref.watch(
      selectedCategoryProvider(widget.ownerId),
    );
    final isEphemeral = chatState.activeConversation?.isEphemeral ?? false;

    ref.listen(chatSessionProvider(widget.ownerId), (prev, next) {
      if (prev?.messages.length != next.messages.length ||
          (next.messages.isNotEmpty &&
              prev?.messages.lastOrNull?.content !=
                  next.messages.lastOrNull?.content)) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToBottomIfNeeded(),
        );
      }
    });

    final categoryLabel = switch (selectedCategory) {
      ModelCategory.fast => s.modelsFastTitle,
      ModelCategory.standard => s.modelsStandardTitle,
      ModelCategory.advanced => s.modelsAdvancedTitle,
    };

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('chat.back'),
          tooltip: 'Назад к ассистенту',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/assistant');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              chatState.activeConversation?.title ?? s.assistantTab,
              style: BuilderType.h3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            InkWell(
              key: const Key('assistant.chooseModel'),
              onTap: () => context.push('/assistant/models'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BuilderIcon(
                    BuilderGlyph.robot,
                    size: 12,
                    color: BuilderColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '$categoryLabel ›',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BuilderType.small.copyWith(
                        color: BuilderColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('assistant.historyBtn'),
            icon: const Icon(Icons.history),
            tooltip: 'История разговоров',
            onPressed: () =>
                ConversationHistorySheet.show(context, ownerId: widget.ownerId),
          ),
          IconButton(
            key: const Key('assistant.settingsBtn'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Настройки ассистента',
            onPressed: () => context.push('/assistant/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_run != null && !_skillSent)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: _SkillRunCard(
                      draft: _run!,
                      onCancel: () => setState(() => _run = null),
                      busy:
                          chatState.isLoading ||
                          chatState.isGenerating ||
                          _skillSending,
                      onRun: _sendSkill,
                    ),
                  ),
                ),
              ),
            // Ephemeral mode notice
            if (isEphemeral)
              Container(
                color: BuilderColors.warningTint,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.visibility_off_outlined,
                      size: 16,
                      color: BuilderColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Режим без сохранения истории: сообщения не записываются на устройство.',
                        style: BuilderType.small.copyWith(
                          color: BuilderColors.ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: chatState.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : chatState.messages.isEmpty
                  ? _buildEmptyState()
                  : _buildMessageList(chatState),
            ),
            if (chatState.isSlowResponse)
              Container(
                color: BuilderColors.primaryTint,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ответ формируется дольше 10 секунд... Сервер продолжает генерацию.',
                        style: BuilderType.small.copyWith(
                          color: BuilderColors.inkSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _buildComposer(chatState),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BuilderIcon(
                BuilderGlyph.robot,
                size: 48,
                color: BuilderColors.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Чем помочь на уроке или в подготовке?',
                textAlign: TextAlign.center,
                style: BuilderType.h2,
              ),
              const SizedBox(height: 8),
              Text(
                'Выберите один из стартовых вопросов или напишите свой собственный запрос ниже:',
                textAlign: TextAlign.center,
                style: BuilderType.body.copyWith(
                  color: BuilderColors.inkSecondary,
                ),
              ),
              const SizedBox(height: 24),
              _buildPromptCard(
                keyStr: 'chat.promptOhm',
                title: 'Объясни закон Ома простыми словами',
                subtitle: 'Физика • Наглядная аналогия с потоком воды',
                prompt:
                    'Объясни закон Ома простыми словами для школьников 8 класса с наглядной аналогией.',
              ),
              const SizedBox(height: 12),
              _buildPromptCard(
                keyStr: 'chat.promptLesson',
                title: 'Составь план урока на 45 минут',
                subtitle: 'Методика • Цели, этапы и критерии оценки',
                prompt:
                    'Составь подробный план урока на 45 минут по теме: «Строение клетки».',
              ),
              const SizedBox(height: 12),
              _buildPromptCard(
                keyStr: 'chat.promptMath',
                title: 'Реши задачу с пошаговой проверкой',
                subtitle: 'Математика • Алгоритм решения и самопроверка',
                prompt:
                    'Реши квадратное уравнение 2x² - 5x + 2 = 0 с пошаговыми комментариями.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromptCard({
    required String keyStr,
    required String title,
    required String subtitle,
    required String prompt,
  }) {
    return InkWell(
      key: Key(keyStr),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _handleSend(prompt),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: BuilderColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BuilderColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: BuilderType.label.copyWith(color: BuilderColors.primary),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: BuilderType.small.copyWith(
                color: BuilderColors.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(ChatState chatState) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: chatState.messages.length,
      itemBuilder: (context, index) {
        final message = chatState.messages[index];

        if (message.isSystem) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: BuilderColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: BuilderColors.line),
                ),
                child: Text(
                  message.content,
                  style: BuilderType.small.copyWith(
                    color: BuilderColors.inkSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }

        if (message.isUser) {
          return Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(left: 48, bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: BuilderColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                skillRequestSummary(
                  message.content,
                  isKk: Localizations.localeOf(context).languageCode == 'kk',
                ),
                style: BuilderType.body.copyWith(color: Colors.white),
              ),
            ),
          );
        }

        // Assistant Message Bubble
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(right: 32, bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: BuilderColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BuilderColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BuilderIcon(
                      BuilderGlyph.robot,
                      size: 16,
                      color: BuilderColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Ассистент',
                      style: BuilderType.small.copyWith(
                        fontWeight: FontWeight.w700,
                        color: BuilderColors.inkSecondary,
                      ),
                    ),
                    if (message.modelId != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(${message.modelId})',
                        style: BuilderType.small.copyWith(
                          color: BuilderColors.inkSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (message.status == MessageStatus.streaming)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (message.status == MessageStatus.interrupted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: BuilderColors.warningTint,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Остановлено',
                          style: BuilderType.small.copyWith(
                            color: BuilderColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (message.content.isNotEmpty)
                  MarkdownMessageView(text: message.content)
                else if (message.status == MessageStatus.streaming)
                  Text(
                    'Мышление...',
                    style: BuilderType.body.copyWith(
                      color: BuilderColors.inkSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (message.status == MessageStatus.error) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: BuilderColors.warningTint,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: BuilderColors.warning),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 16,
                              color: BuilderColors.warning,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                message.errorMessage ??
                                    'Не удалось получить ответ от сервера.',
                                style: BuilderType.small.copyWith(
                                  color: BuilderColors.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            BuilderButton(
                              key: const Key('chat.retryBtn'),
                              label: 'Повторить запрос',
                              variant: BuilderButtonVariant.secondary,
                              onPressed: () => ref
                                  .read(
                                    chatSessionProvider(
                                      widget.ownerId,
                                    ).notifier,
                                  )
                                  .retryLast(),
                            ),
                            if (message.requestId != null) ...[
                              BuilderButton(
                                key: Key('chat.errorTraceBtn_${message.id}'),
                                label: 'Под капотом',
                                variant: BuilderButtonVariant.text,
                                onPressed: () => TraceSheet.show(
                                  context,
                                  requestId: message.requestId!,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                if (message.status == MessageStatus.completed ||
                    message.status == MessageStatus.interrupted) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (message.content.trim().isNotEmpty)
                        IconButton(
                          key: const Key('chat.copyBtn'),
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          tooltip: 'Копировать ответ',
                          onPressed: () async {
                            try {
                              await Clipboard.setData(
                                ClipboardData(text: message.content),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Ответ скопирован'),
                                ),
                              );
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Не удалось скопировать ответ. Попробуйте ещё раз.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      if (message.requestId?.trim().isNotEmpty == true)
                        IconButton(
                          key: Key('chat.traceBtn_${message.id}'),
                          icon: const Icon(Icons.tune, size: 16),
                          tooltip: 'Под капотом',
                          onPressed: () => TraceSheet.show(
                            context,
                            requestId: message.requestId!,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildComposer(ChatState chatState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: BuilderColors.surface,
        border: Border(top: BorderSide(color: BuilderColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            key: const Key('chat.skillsBtn'),
            icon: const BuilderIcon(
              BuilderGlyph.bolt,
              color: BuilderColors.primary,
            ),
            tooltip: Localizations.localeOf(context).languageCode == 'kk'
                ? 'Дағдылар'
                : 'Навыки',
            onPressed: _pickSkill,
          ),
          Expanded(
            child: TextField(
              key: const Key('chat.inputField'),
              controller: _textController,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Напишите сообщение...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _handleSend(),
            ),
          ),
          const SizedBox(width: 8),
          if (chatState.isGenerating)
            IconButton.filled(
              key: const Key('chat.stopBtn'),
              icon: const Icon(Icons.stop),
              style: IconButton.styleFrom(
                backgroundColor: BuilderColors.warning,
              ),
              tooltip: 'Остановить генерацию',
              onPressed: () => ref
                  .read(chatSessionProvider(widget.ownerId).notifier)
                  .stopGeneration(),
            )
          else
            IconButton.filled(
              key: const Key('chat.sendBtn'),
              icon: const Icon(Icons.arrow_upward),
              style: IconButton.styleFrom(
                backgroundColor: BuilderColors.primary,
              ),
              tooltip: 'Отправить',
              onPressed: () => _handleSend(),
            ),
        ],
      ),
    );
  }

  Widget _buildResumeCourseBanner(BuildContext context) {
    final overallAsync = ref.watch(
      overallCourseProgressProvider(widget.ownerId),
    );
    return overallAsync.maybeWhen(
      data: (overall) {
        if (overall.isAllCompleted || overall.activeLevelId == null) {
          return const SizedBox.shrink();
        }
        final level = CourseCatalog.getLevel(overall.activeLevelId!);
        final levelTitle = level?.title ?? 'Уровень ${overall.activeLevelId}';
        final stepName = overall.activeStep.title;

        return Container(
          key: const Key('assistant.resumeLessonBanner'),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: BuilderColors.primaryTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: BuilderColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () =>
                context.push('/course/lesson/${overall.activeLevelId}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.play_circle_outline,
                    color: BuilderColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Продолжить урок',
                              style: BuilderType.label.copyWith(
                                color: BuilderColors.primary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: BuilderColors.primary.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                stepName,
                                style: BuilderType.small.copyWith(
                                  fontSize: 11,
                                  color: BuilderColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          levelTitle,
                          style: BuilderType.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: BuilderColors.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: BuilderColors.primary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Ready-to-run card shown above the chat before a skill request is sent.
class _SkillRunCard extends StatelessWidget {
  const _SkillRunCard({
    required this.draft,
    required this.busy,
    required this.onRun,
    required this.onCancel,
  });
  final SkillRunDraft draft;
  final bool busy;
  final VoidCallback onRun;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final kk = Localizations.localeOf(context).languageCode == 'kk';
    String t(String ru, String kz) => kk ? kz : ru;
    final skill = draft.skill;
    return BuilderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuilderIconTile(BuilderGlyph.bolt),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(skill.name, style: BuilderType.h3),
                    Text(
                      t('Готов к запуску', 'Іске қосуға дайын'),
                      style: BuilderType.small,
                    ),
                  ],
                ),
              ),
              BuilderIconButton(
                icon: BuilderGlyph.close,
                label: t('Отменить', 'Бас тарту'),
                onPressed: busy ? null : onCancel,
              ),
            ],
          ),
          if (draft.inputs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final input in draft.inputs.entries)
                  Chip(
                    label: Text(
                      '${input.key}: ${input.value}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            skill.sources.isEmpty
                ? t(
                    'Ассистент использует только то, что вы указали выше.',
                    'Көмекші тек жоғарыда көрсеткеніңізді пайдаланады.',
                  )
                : '${t('Заявленные источники', 'Мәлімделген дереккөздер')}: ${skill.sources.join('; ')}. ${t('Их содержимое не загружается — ассистент видит только указанное выше.', 'Олардың мазмұны жүктелмейді — көмекші тек жоғарыда көрсетілгенді көреді.')}',
            style: BuilderType.small,
          ),
          const SizedBox(height: 12),
          BuilderButton(
            key: const Key('skill.send'),
            label: busy
                ? t('Запускаем…', 'Іске қосылуда…')
                : t('Запустить', 'Іске қосу'),
            icon: BuilderGlyph.send,
            onPressed: busy ? null : onRun,
          ),
        ],
      ),
    );
  }
}
