import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/lab_run_models.dart';
import '../infrastructure/lab_runtime_api.dart';

class LabAgentRunConfig {
  final String agentId;
  final LabModelInfo? model;
  final bool allowSave;
  final bool allowSearch;
  final bool useDialogue;

  const LabAgentRunConfig({
    required this.agentId,
    this.model,
    this.allowSave = false,
    this.allowSearch = false,
    this.useDialogue = false,
  });
}

class LabRunState {
  final String draftText;
  final List<String> pendingImages;
  final bool isSending;
  final bool isOffline;
  final bool isLoadingDialogue;
  final bool isDialogueReady;
  final List<LabDialogueTurn> turns;
  final bool hasOlderTurns;
  final String? sendingPrompt;
  final LabRun? activeRun;
  final List<String> outputVersions;
  final bool showPreviousVersion;
  final String? activeIdempotencyKey;
  final String? lastPromptForRetry;
  final LabApiException? error;
  final String? compatibilityBlockReason;

  const LabRunState({
    this.draftText = '',
    this.pendingImages = const [],
    this.isSending = false,
    this.isOffline = false,
    this.isLoadingDialogue = false,
    this.isDialogueReady = false,
    this.turns = const [],
    this.hasOlderTurns = false,
    this.sendingPrompt,
    this.activeRun,
    this.outputVersions = const [],
    this.showPreviousVersion = false,
    this.activeIdempotencyKey,
    this.lastPromptForRetry,
    this.error,
    this.compatibilityBlockReason,
  });

  String? get displayedOutput {
    if (outputVersions.isEmpty) return activeRun?.finalOutput;
    if (showPreviousVersion && outputVersions.length >= 2) {
      return outputVersions[outputVersions.length - 2];
    }
    return outputVersions.last;
  }

  bool get canToggleBeforeAfter => outputVersions.length >= 2;

  bool get hasToolFailure {
    final run = activeRun;
    if (run == null) return false;
    for (final evt in run.events) {
      if (evt.eventType == 'tool_rejected') return true;
      if (evt.eventType == 'tool_result') {
        final result = evt.payload['result'];
        if (result is Map && result['error'] != null) return true;
      }
    }
    return false;
  }

  LabRunState copyWith({
    String? draftText,
    List<String>? pendingImages,
    bool? isSending,
    bool? isOffline,
    bool? isLoadingDialogue,
    bool? isDialogueReady,
    List<LabDialogueTurn>? turns,
    bool? hasOlderTurns,
    String? sendingPrompt,
    bool clearSendingPrompt = false,
    LabRun? activeRun,
    bool clearActiveRun = false,
    List<String>? outputVersions,
    bool? showPreviousVersion,
    String? activeIdempotencyKey,
    String? lastPromptForRetry,
    LabApiException? error,
    bool clearError = false,
    String? compatibilityBlockReason,
    bool clearCompatibility = false,
  }) {
    return LabRunState(
      draftText: draftText ?? this.draftText,
      pendingImages: pendingImages ?? this.pendingImages,
      isSending: isSending ?? this.isSending,
      isOffline: isOffline ?? this.isOffline,
      isLoadingDialogue: isLoadingDialogue ?? this.isLoadingDialogue,
      isDialogueReady: isDialogueReady ?? this.isDialogueReady,
      turns: turns ?? this.turns,
      hasOlderTurns: hasOlderTurns ?? this.hasOlderTurns,
      sendingPrompt: clearSendingPrompt
          ? null
          : (sendingPrompt ?? this.sendingPrompt),
      activeRun: clearActiveRun ? null : (activeRun ?? this.activeRun),
      outputVersions: outputVersions ?? this.outputVersions,
      showPreviousVersion: showPreviousVersion ?? this.showPreviousVersion,
      activeIdempotencyKey: activeIdempotencyKey ?? this.activeIdempotencyKey,
      lastPromptForRetry: lastPromptForRetry ?? this.lastPromptForRetry,
      error: clearError ? null : (error ?? this.error),
      compatibilityBlockReason: clearCompatibility
          ? null
          : (compatibilityBlockReason ?? this.compatibilityBlockReason),
    );
  }
}

class LabRunController extends Notifier<LabRunState> {
  final LabRuntimeApi api;
  final LabAgentRunConfig config;
  bool _inFlight = false;
  String? _conversationId;
  String? _olderCursor;
  List<String> _retryImages = const [];
  bool _retryPending = false;
  bool _recovering = false;

  LabRunController({required this.api, required this.config});

  @override
  LabRunState build() => const LabRunState();

  LabDialogueApi? get _dialogueApi =>
      config.useDialogue && api is LabDialogueApi
      ? api as LabDialogueApi
      : null;

  Future<void> loadDialogue({bool older = false}) async {
    final dialogue = _dialogueApi;
    if (dialogue == null || state.isLoadingDialogue || _inFlight) return;
    final cursor = older ? _olderCursor : null;
    if (older && cursor == null) return;
    state = state.copyWith(isLoadingDialogue: true, clearError: true);
    try {
      final page = await dialogue.getDialogue(config.agentId, before: cursor);
      if (older && page.conversationId != _conversationId) {
        _olderCursor = null;
        state = state.copyWith(hasOlderTurns: false, isLoadingDialogue: false);
        return;
      }
      if (older) {
        _olderCursor = page.nextBefore;
        final ids = state.turns.map((turn) => turn.run.id).toSet();
        state = state.copyWith(
          turns: [
            ...page.turns.where((turn) => !ids.contains(turn.run.id)),
            ...state.turns,
          ],
          hasOlderTurns: _olderCursor != null,
          isLoadingDialogue: false,
        );
        return;
      }
      final sameDialogue = _conversationId == page.conversationId;
      if (!sameDialogue) _retryPending = false;
      final first = page.turns.firstOrNull?.run.id;
      final overlap = sameDialogue && first != null
          ? state.turns.indexWhere((turn) => turn.run.id == first)
          : -1;
      final turns = overlap > 0
          ? [...state.turns.take(overlap), ...page.turns]
          : page.turns;
      _conversationId = page.conversationId;
      if (overlap <= 0) _olderCursor = page.nextBefore;
      final latest = page.turns.lastOrNull?.run;
      state = state.copyWith(
        turns: turns,
        hasOlderTurns: _olderCursor != null,
        isDialogueReady: true,
        isLoadingDialogue: false,
        isOffline: false,
        activeRun: latest,
        clearActiveRun: latest == null,
        isSending: latest?.status == 'running',
      );
    } on LabApiException catch (e) {
      state = state.copyWith(
        isLoadingDialogue: false,
        isOffline: e.isOffline,
        error: e,
      );
    } catch (_) {
      state = state.copyWith(
        isLoadingDialogue: false,
        error: const LabApiException(
          code: 'dialogue.load-error',
          message: 'Не удалось загрузить историю диалога.',
        ),
      );
    }
  }

  List<LabDialogueTurn> _upsertTurn(LabRun run, {String? prompt}) {
    final turns = List<LabDialogueTurn>.of(state.turns);
    final index = turns.indexWhere((turn) => turn.run.id == run.id);
    if (index >= 0) {
      turns[index] = LabDialogueTurn(prompt: turns[index].prompt, run: run);
    } else if (prompt != null) {
      turns.add(LabDialogueTurn(prompt: prompt, run: run));
    }
    return turns;
  }

  void updateDraft(String text) {
    state = state.copyWith(draftText: text, clearCompatibility: true);
  }

  void toggleBeforeAfter() {
    if (!state.canToggleBeforeAfter) return;
    state = state.copyWith(showPreviousVersion: !state.showPreviousVersion);
  }

  String? checkCompatibility({bool hasImages = false}) {
    final model = config.model;
    if (model == null || model.modelId.isEmpty) {
      return 'Выберите модель в настройках агента перед отправкой.';
    }
    if ((config.allowSave || config.allowSearch) && !model.supportsTools) {
      return 'Модель ${model.modelId} не поддерживает инструменты (save/search). '
          'Отключите инструменты или смените модель.';
    }
    if (hasImages && !model.supportsVision) {
      return 'Модель ${model.modelId} не поддерживает изображения. Смените модель.';
    }
    return null;
  }

  String _generateIdempotencyKey() {
    final rand = Random.secure();
    final suffix = List.generate(
      8,
      (_) => rand.nextInt(16).toRadixString(16),
    ).join();
    return 'run-${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }

  Future<void> sendMessage([String? overrideText]) async {
    if (_inFlight) return;
    final prompt = (overrideText ?? state.draftText).trim();
    if (prompt.isEmpty) return;

    final blockReason = checkCompatibility(
      hasImages: state.pendingImages.isNotEmpty,
    );
    if (blockReason != null) {
      state = state.copyWith(compatibilityBlockReason: blockReason);
      return;
    }

    if (config.useDialogue) {
      if (_conversationId == null || state.isLoadingDialogue) {
        await loadDialogue();
        return;
      }
      if (state.activeRun?.activePendingAction != null || state.isSending) {
        return;
      }
      if (_retryPending && state.lastPromptForRetry == prompt) {
        await retryLast();
        return;
      }
      _retryImages = List<String>.of(state.pendingImages);
    }
    final key = _generateIdempotencyKey();
    await _executeRun(
      prompt: prompt,
      idempotencyKey: key,
      clearDraftOnSuccess: true,
    );
  }

  Future<void> retryLast() async {
    if (_inFlight) return;
    if (config.useDialogue && !_retryPending) {
      await loadDialogue();
      return;
    }
    if (config.useDialogue && _conversationId == null) return;
    final prompt = state.lastPromptForRetry ?? state.draftText.trim();
    if (prompt.isEmpty) return;
    // Reuse the same Idempotency-Key across retries / double-taps
    final key = state.activeIdempotencyKey ?? _generateIdempotencyKey();
    await _executeRun(
      prompt: prompt,
      idempotencyKey: key,
      clearDraftOnSuccess: true,
    );
  }

  Future<void> _executeRun({
    required String prompt,
    required String idempotencyKey,
    required bool clearDraftOnSuccess,
  }) async {
    _inFlight = true;
    state = state.copyWith(
      isSending: true,
      isOffline: false,
      activeIdempotencyKey: idempotencyKey,
      lastPromptForRetry: prompt,
      sendingPrompt: config.useDialogue ? prompt : null,
      clearError: true,
      clearCompatibility: true,
    );

    try {
      final dialogue = _dialogueApi;
      final run = dialogue == null
          ? await api.createRun(
              agentId: config.agentId,
              prompt: prompt,
              idempotencyKey: idempotencyKey,
              imageDataUris: state.pendingImages,
            )
          : await dialogue.createDialogueTurn(
              agentId: config.agentId,
              conversationId: _conversationId!,
              prompt: prompt,
              idempotencyKey: idempotencyKey,
              imageDataUris: _retryImages,
            );
      _retryPending = false;
      final versions = List<String>.from(state.outputVersions);
      if (run.finalOutput != null && run.finalOutput!.isNotEmpty) {
        versions.add(run.finalOutput!);
      }
      state = state.copyWith(
        isSending: run.status == 'running',
        clearSendingPrompt: true,
        activeRun: run,
        turns: config.useDialogue ? _upsertTurn(run, prompt: prompt) : null,
        outputVersions: versions,
        showPreviousVersion: false,
        draftText:
            clearDraftOnSuccess &&
                (!config.useDialogue || state.draftText.trim() == prompt)
            ? ''
            : state.draftText,
      );
    } on LabApiException catch (e) {
      _retryPending =
          config.useDialogue &&
          !const [
            'dialogue.changed',
            'dialogue.busy',
            'idempotency.key-reused',
          ].contains(e.code);
      state = state.copyWith(
        isSending: false,
        isOffline: e.isOffline,
        clearSendingPrompt: true,
        error: e,
      );
    } catch (e) {
      _retryPending = config.useDialogue;
      state = state.copyWith(
        isSending: false,
        clearSendingPrompt: true,
        error: LabApiException(
          code: 'run.unexpected',
          message: 'Не удалось выполнить запуск: $e',
        ),
      );
    } finally {
      _inFlight = false;
    }
  }

  Future<void> cancelActiveRun() async {
    final run = state.activeRun;
    if (run == null) return;
    try {
      final updated = await api.cancelRun(run.id);
      state = state.copyWith(
        activeRun: updated,
        isSending: false,
        turns: config.useDialogue ? _upsertTurn(updated) : null,
      );
    } on LabApiException catch (e) {
      state = state.copyWith(error: e, isOffline: e.isOffline);
    }
  }

  Future<void> resolvePendingAction(String decision) async {
    final run = state.activeRun;
    final action = run?.activePendingAction;
    if (run == null || action == null || _inFlight) return;
    _inFlight = true;
    state = state.copyWith(isSending: true, clearError: true);
    try {
      final updated = await api.resolveAction(
        runId: run.id,
        actionId: action.id,
        decision: decision,
      );
      final versions = List<String>.from(state.outputVersions);
      if (updated.finalOutput != null && updated.finalOutput!.isNotEmpty) {
        versions.add(updated.finalOutput!);
      }
      state = state.copyWith(
        isSending: false,
        activeRun: updated,
        turns: config.useDialogue ? _upsertTurn(updated) : null,
        outputVersions: versions,
        showPreviousVersion: false,
      );
    } on LabApiException catch (e) {
      state = state.copyWith(
        isSending: false,
        error: e,
        isOffline: e.isOffline,
      );
    } finally {
      _inFlight = false;
    }
  }

  Future<void> refreshDialogueStream() async {
    final dialogue = _dialogueApi;
    final prompt = state.sendingPrompt;
    final key = state.activeIdempotencyKey;
    if (!_inFlight || prompt == null || key == null || dialogue == null) {
      await recoverOnResumed();
      return;
    }
    if (_recovering) return;
    _recovering = true;
    try {
      final page = await dialogue.getDialogue(config.agentId);
      if (!_inFlight ||
          state.activeIdempotencyKey != key ||
          page.conversationId != _conversationId) {
        return;
      }
      final turn = page.turns.where((item) => item.run.requestKey == key).firstOrNull;
      if (turn == null ||
          state.activeRun?.id == turn.run.id &&
              state.activeRun?.status == 'cancelled' &&
              turn.run.status == 'running') {
        return;
      }
      state = state.copyWith(
        turns: _upsertTurn(turn.run, prompt: prompt),
        activeRun: turn.run,
      );
    } on LabApiException {
      // A progress read is best-effort. The original request or an explicit
      // retry still resolves the turn using its stable request key.
    } finally {
      _recovering = false;
    }
  }

  Future<void> recoverOnResumed() async {
    if (_recovering || _inFlight) return;
    final run = state.activeRun;
    if (run == null ||
        (run.status != 'running' && run.status != 'awaiting_confirmation')) {
      if (config.useDialogue) await loadDialogue();
      return;
    }
    _recovering = true;
    try {
      final refreshed = await api.getRun(run.id);
      final versions = List<String>.from(state.outputVersions);
      if (refreshed.finalOutput != null &&
          refreshed.finalOutput!.isNotEmpty &&
          (versions.isEmpty || versions.last != refreshed.finalOutput)) {
        versions.add(refreshed.finalOutput!);
      }
      state = state.copyWith(
        activeRun: refreshed,
        turns: config.useDialogue ? _upsertTurn(refreshed) : null,
        outputVersions: versions,
        isSending: refreshed.status == 'running',
      );
    } on LabApiException catch (e) {
      state = state.copyWith(error: e, isOffline: e.isOffline);
    } finally {
      _recovering = false;
    }
  }
}
