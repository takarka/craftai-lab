import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/lab_run_models.dart';
import '../infrastructure/lab_runtime_api.dart';

class LabAgentRunConfig {
  final String agentId;
  final LabModelInfo? model;
  final bool allowSave;
  final bool allowSearch;

  const LabAgentRunConfig({
    required this.agentId,
    this.model,
    this.allowSave = false,
    this.allowSearch = false,
  });
}

class LabRunState {
  final String draftText;
  final List<String> pendingImages;
  final bool isSending;
  final bool isOffline;
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
    LabRun? activeRun,
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
      activeRun: activeRun ?? this.activeRun,
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

  LabRunController({
    required this.api,
    required this.config,
  });

  @override
  LabRunState build() => const LabRunState();

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
    final suffix = List.generate(8, (_) => rand.nextInt(16).toRadixString(16)).join();
    return 'run-${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }

  Future<void> sendMessage([String? overrideText]) async {
    if (_inFlight) return;
    final prompt = (overrideText ?? state.draftText).trim();
    if (prompt.isEmpty) return;

    final blockReason = checkCompatibility(hasImages: state.pendingImages.isNotEmpty);
    if (blockReason != null) {
      state = state.copyWith(compatibilityBlockReason: blockReason);
      return;
    }

    final key = _generateIdempotencyKey();
    await _executeRun(prompt: prompt, idempotencyKey: key, clearDraftOnSuccess: true);
  }

  Future<void> retryLast() async {
    if (_inFlight) return;
    final prompt = state.lastPromptForRetry ?? state.draftText.trim();
    if (prompt.isEmpty) return;
    // Reuse the same Idempotency-Key across retries / double-taps
    final key = state.activeIdempotencyKey ?? _generateIdempotencyKey();
    await _executeRun(prompt: prompt, idempotencyKey: key, clearDraftOnSuccess: true);
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
      clearError: true,
      clearCompatibility: true,
    );

    try {
      final run = await api.createRun(
        agentId: config.agentId,
        prompt: prompt,
        idempotencyKey: idempotencyKey,
        imageDataUris: state.pendingImages,
      );
      final versions = List<String>.from(state.outputVersions);
      if (run.finalOutput != null && run.finalOutput!.isNotEmpty) {
        versions.add(run.finalOutput!);
      }
      state = state.copyWith(
        isSending: false,
        activeRun: run,
        outputVersions: versions,
        showPreviousVersion: false,
        draftText: clearDraftOnSuccess ? '' : state.draftText,
      );
    } on LabApiException catch (e) {
      state = state.copyWith(
        isSending: false,
        isOffline: e.isOffline,
        error: e,
      );
    } catch (e) {
      state = state.copyWith(
        isSending: false,
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
      state = state.copyWith(activeRun: updated, isSending: false);
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
        outputVersions: versions,
        showPreviousVersion: false,
      );
    } on LabApiException catch (e) {
      state = state.copyWith(isSending: false, error: e, isOffline: e.isOffline);
    } finally {
      _inFlight = false;
    }
  }

  Future<void> recoverOnResumed() async {
    final run = state.activeRun;
    if (run == null) return;
    if (run.status != 'running' && run.status != 'awaiting_confirmation') {
      return;
    }
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
        outputVersions: versions,
        isSending: refreshed.status == 'running',
      );
    } on LabApiException catch (e) {
      state = state.copyWith(error: e, isOffline: e.isOffline);
    }
  }
}
