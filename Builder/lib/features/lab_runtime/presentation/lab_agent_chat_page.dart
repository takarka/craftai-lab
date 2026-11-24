import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/lab_run_models.dart';
import 'lab_run_controller.dart';
import 'lab_run_trace_page.dart';

class LabAgentChatPage extends ConsumerStatefulWidget {
  final String agentName;
  final LabRunController controller;
  final VoidCallback? onOpenSettings;

  const LabAgentChatPage({
    super.key,
    required this.agentName,
    required this.controller,
    this.onOpenSettings,
  });

  @override
  ConsumerState<LabAgentChatPage> createState() => _LabAgentChatPageState();
}

class _LabAgentChatPageState extends ConsumerState<LabAgentChatPage>
    with WidgetsBindingObserver {
  late final TextEditingController _textController;
  final ScrollController _dialogueScroll = ScrollController();
  Timer? _runningTimer;
  late final NotifierProvider<LabRunController, LabRunState> _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textController = TextEditingController();
    _provider = NotifierProvider<LabRunController, LabRunState>(
      () => widget.controller,
    );
    if (widget.controller.config.useDialogue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(_provider.notifier).loadDialogue();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    _dialogueScroll.dispose();
    _runningTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(_provider.notifier).recoverOnResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final notifier = ref.read(_provider.notifier);
    final useDialogue = notifier.config.useDialogue;
    if (useDialogue) {
      ref.listen(_provider, (previous, next) {
        final oldLast = previous?.turns.lastOrNull?.run;
        final newLast = next.turns.lastOrNull?.run;
        if (newLast?.status == 'running') {
          _runningTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
            if (mounted) ref.read(_provider.notifier).recoverOnResumed();
          });
        } else {
          _runningTimer?.cancel();
          _runningTimer = null;
        }
        if (oldLast?.id != newLast?.id ||
            oldLast?.status != newLast?.status ||
            next.sendingPrompt != null && previous?.sendingPrompt == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _dialogueScroll.hasClients) {
              _dialogueScroll.jumpTo(_dialogueScroll.position.maxScrollExtent);
            }
          });
        }
      });
    }

    if (_textController.text != state.draftText && !state.isSending) {
      _textController.value = TextEditingValue(
        text: state.draftText,
        selection: TextSelection.collapsed(offset: state.draftText.length),
      );
    }

    final run = state.activeRun;
    final pendingAction = run?.activePendingAction;
    final output = state.displayedOutput;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.agentName),
        actions: [
          if (run != null)
            IconButton(
              tooltip: 'Как выполнено',
              icon: const Icon(Icons.analytics_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LabRunTracePage(
                      runId: run.id,
                      api: widget.controller.api,
                    ),
                  ),
                );
              },
            ),
          if (widget.onOpenSettings != null)
            IconButton(
              tooltip: 'Настройки агента',
              icon: const Icon(Icons.tune),
              onPressed: widget.onOpenSettings,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildLimitsBanner(context, run),
          Expanded(
            child: ListView(
              controller: useDialogue ? _dialogueScroll : null,
              padding: const EdgeInsets.all(16),
              children: [
                if (useDialogue) ...[
                  if (state.hasOlderTurns)
                    TextButton(
                      onPressed: state.isLoadingDialogue
                          ? null
                          : () => notifier.loadDialogue(older: true),
                      child: const Text('Показать ранние сообщения'),
                    ),
                  if (state.isLoadingDialogue && state.turns.isEmpty)
                    const Center(child: CircularProgressIndicator()),
                  if (state.isDialogueReady && state.turns.isEmpty && state.sendingPrompt == null)
                    const Text('Напишите агенту, чтобы начать диалог.'),
                  for (final turn in state.turns) ...[
                    _buildPrompt(turn.prompt),
                    if (turn.run.finalOutput case final String output when output.isNotEmpty)
                      _buildOutputCard(context, output, state, notifier, turn.run),
                    if (turn.run.status == 'failed')
                      _buildAlertCard(
                        context,
                        title: 'Ответ не получен',
                        message: turn.run.errorMessage ?? 'История диалога сохранена.',
                        isError: true,
                      ),
                    if (turn.run.status == 'cancelled')
                      const Text('Ответ остановлен.'),
                  ],
                  if (state.sendingPrompt case final String prompt)
                    _buildPrompt(prompt),
                  if (state.isSending)
                    const LinearProgressIndicator(),
                ],
                if (state.compatibilityBlockReason != null)
                  _buildAlertCard(
                    context,
                    title: 'Модель несовместима',
                    message: state.compatibilityBlockReason!,
                    isError: true,
                  ),
                if (state.error != null)
                  _buildErrorCard(context, state.error!, notifier),
                if (pendingAction != null)
                  _buildConfirmationCard(
                    context,
                    pendingAction,
                    notifier,
                    state.isSending,
                  ),
                if (state.hasToolFailure && run != null)
                  _buildAlertCard(
                    context,
                    title: 'Инструмент завершился с ошибкой',
                    message:
                        'Не все вызовы инструментов прошли успешно. Проверьте детали в разделе «Как выполнено».',
                    isError: true,
                  ),
                if (!useDialogue && output != null && output.isNotEmpty)
                  _buildOutputCard(context, output, state, notifier, run),
              ],
            ),
          ),
          _buildInputBar(context, state, notifier),
        ],
      ),
    );
  }

  Widget _buildPrompt(String prompt) {
    return Align(
      alignment: Alignment.centerRight,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12, left: 36),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(prompt),
        ),
      ),
    );
  }

  Widget _buildLimitsBanner(BuildContext context, LabRun? run) {
    final used = run?.toolCallsCount ?? 0;
    final stopText = run?.stopReason != null
        ? ' · Остановка: ${run!.stopReason}'
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        'Лимиты: $used/3 инструментов · 60 с · 15 мин подтверждение$stopText',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _buildAlertCard(
    BuildContext context, {
    required String title,
    required String message,
    bool isError = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: isError ? scheme.errorContainer : scheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isError
                    ? scheme.onErrorContainer
                    : scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: TextStyle(
                color: isError
                    ? scheme.onErrorContainer
                    : scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(
    BuildContext context,
    LabApiException error,
    LabRunController notifier,
  ) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error.isOffline ? 'Нет сети' : 'Ошибка выполнения',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(error.message),
            const SizedBox(height: 4),
            Text('Следующий шаг: ${error.nextStep}'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => notifier.retryLast(),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationCard(
    BuildContext context,
    LabPendingAction action,
    LabRunController notifier,
    bool isSending,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Требуется подтверждение действия',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Инструмент: ${action.toolName}'),
            Text('Название: ${action.params['title'] ?? '—'}'),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: isSending
                      ? null
                      : () => notifier.resolvePendingAction('approve'),
                  child: const Text('Подтвердить'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: isSending
                      ? null
                      : () => notifier.resolvePendingAction('deny'),
                  child: const Text('Отклонить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputCard(
    BuildContext context,
    String output,
    LabRunState state,
    LabRunController notifier,
    LabRun? run,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    !notifier.config.useDialogue && state.showPreviousVersion
                        ? 'Предыдущая версия ответа (до)'
                        : 'Ответ агента',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (!notifier.config.useDialogue && state.canToggleBeforeAfter)
                  TextButton(
                    onPressed: notifier.toggleBeforeAfter,
                    child: Text(
                      state.showPreviousVersion
                          ? 'Показать «после»'
                          : 'Показать «до»',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(output),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: output));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ответ скопирован')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Копировать'),
                ),
                TextButton.icon(
                  onPressed: () {
                    SharePlus.instance.share(ShareParams(text: output));
                  },
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Поделиться'),
                ),
                if (run != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LabRunTracePage(
                            runId: run.id,
                            api: widget.controller.api,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.timeline, size: 18),
                    label: const Text('Как выполнено'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(
    BuildContext context,
    LabRunState state,
    LabRunController notifier,
  ) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label: 'Поле запроса к агенту',
                child: TextField(
                  controller: _textController,
                  onChanged: notifier.updateDraft,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Введите задачу для агента...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (state.isSending)
              IconButton.filled(
                tooltip: 'Остановить',
                onPressed: notifier.config.useDialogue && state.activeRun?.status != 'running'
                    ? null
                    : notifier.cancelActiveRun,
                icon: const Icon(Icons.stop),
              )
            else
              IconButton.filled(
                tooltip: 'Отправить',
                onPressed: notifier.config.useDialogue &&
                    (state.isLoadingDialogue || state.activeRun?.activePendingAction != null)
                    ? null
                    : () => notifier.sendMessage(_textController.text),
                icon: const Icon(Icons.send),
              ),
          ],
        ),
      ),
    );
  }
}
