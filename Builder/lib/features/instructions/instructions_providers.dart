import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/storage_providers.dart';
import '../assistant/assistant_providers.dart';
import '../chat/domain/context_assembler.dart';
import '../chat/chat_providers.dart';
import '../chat/domain/chat_stream_event.dart';
import '../models/model_providers.dart';
import '../models/domain/model_category.dart';
import '../trace/domain/request_trace.dart';
import '../trace/trace_providers.dart';
import 'domain/instruction_models.dart';
import 'domain/instructions_repository.dart';
import 'infrastructure/persistent_instructions_repository.dart';

final instructionsRepositoryProvider = Provider<InstructionsRepository>((ref) {
  final storageDatabase = ref.watch(storageDatabaseProvider);
  if (storageDatabase == null) {
    return InMemoryInstructionsRepository();
  }
  return PersistentInstructionsRepository(database: storageDatabase);
});

final instructionConfigProvider =
    FutureProvider.family<InstructionConfig, String>((ref, ownerId) async {
      final repo = ref.watch(instructionsRepositoryProvider);
      return repo.getInstructionConfig(ownerId);
    });

class TestComparisonResult {
  final String question;
  final String modelCategory;
  final String beforeAnswer;
  final String afterAnswer;
  final RequestTrace beforeTrace;
  final RequestTrace afterTrace;
  final DateTime executedAtUtc;

  const TestComparisonResult({
    required this.question,
    required this.modelCategory,
    required this.beforeAnswer,
    required this.afterAnswer,
    required this.beforeTrace,
    required this.afterTrace,
    required this.executedAtUtc,
  });
}

class InstructionDraftState {
  final InstructionConfig config;
  final bool isSaving;
  final bool isTesting;
  final TestComparisonResult? testResult;
  final String? errorMessage;

  const InstructionDraftState({
    required this.config,
    this.isSaving = false,
    this.isTesting = false,
    this.testResult,
    this.errorMessage,
  });

  InstructionDraftState copyWith({
    InstructionConfig? config,
    bool? isSaving,
    bool? isTesting,
    TestComparisonResult? testResult,
    bool clearTestResult = false,
    String? errorMessage,
  }) {
    return InstructionDraftState(
      config: config ?? this.config,
      isSaving: isSaving ?? this.isSaving,
      isTesting: isTesting ?? this.isTesting,
      testResult: clearTestResult ? null : testResult ?? this.testResult,
      errorMessage: errorMessage,
    );
  }
}

class InstructionDraftNotifier extends Notifier<InstructionDraftState> {
  InstructionDraftNotifier(this.ownerId);
  final String ownerId;
  bool _hasEdits = false;

  @override
  InstructionDraftState build() {
    final initialConfigAsync = ref.watch(instructionConfigProvider(ownerId));
    if (_hasEdits) return state;
    final initialConfig =
        initialConfigAsync.asData?.value ??
        InstructionConfig(
          isRawMode: false,
          rawText: '',
          rules: InstructionPresets.defaultRules
              .map((r) => r.copyWith(ownerId: ownerId))
              .toList(),
        );

    return InstructionDraftState(config: initialConfig);
  }

  void toggleRule(String ruleId, bool isEnabled) {
    _hasEdits = true;
    final updatedRules = state.config.rules.map((rule) {
      if (rule.id == ruleId) {
        return rule.copyWith(isEnabled: isEnabled);
      }
      return rule;
    }).toList();

    state = state.copyWith(
      config: state.config.copyWith(rules: updatedRules),
      errorMessage: null,
    );
  }

  void setMode({required bool isRawMode}) {
    _hasEdits = true;
    if (state.config.isRawMode == isRawMode) return;

    // F11-05: When switching to raw mode, if rawText was empty, seed with current assembled rules.
    // When switching back to structured rules, do NOT overwrite rules with reverse generation.
    String rawText = state.config.rawText;
    if (isRawMode && rawText.trim().isEmpty) {
      rawText = state.config.activeInstructionText;
    }

    state = state.copyWith(
      config: state.config.copyWith(isRawMode: isRawMode, rawText: rawText),
      errorMessage: null,
    );
  }

  void updateRawText(String newText) {
    _hasEdits = true;
    state = state.copyWith(
      config: state.config.copyWith(rawText: newText),
      errorMessage: null,
    );
  }

  Future<void> addCustomRule({
    required InstructionGroup group,
    required String title,
    required String text,
    required String explanation,
  }) async {
    _hasEdits = true;
    final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final newRule = InstructionRule(
      id: newId,
      ownerId: ownerId,
      group: group,
      title: title.trim(),
      text: text.trim(),
      explanation: explanation.trim().isNotEmpty
          ? explanation.trim()
          : 'Пользовательское правило',
      isEnabled: true,
      sortOrder: state.config.rules.length + 1,
      isCustom: true,
      revision: 1,
    );

    final updated = [...state.config.rules, newRule];
    state = state.copyWith(
      config: state.config.copyWith(rules: updated),
      errorMessage: null,
    );

    final repo = ref.read(instructionsRepositoryProvider);
    await repo.addCustomRule(ownerId, newRule);
  }

  void deleteCustomRule(String ruleId) {
    _hasEdits = true;
    final updated = state.config.rules.where((r) => r.id != ruleId).toList();
    state = state.copyWith(
      config: state.config.copyWith(rules: updated),
      errorMessage: null,
    );

    final repo = ref.read(instructionsRepositoryProvider);
    repo.deleteCustomRule(ownerId, ruleId);
  }

  /// Runs test question before & after and records both traces (F11-06)
  Future<TestComparisonResult> runBeforeAfterTest({
    required String question,
    required ModelCategory category,
  }) async {
    _hasEdits = true;
    final activeInstruction = state.config.activeInstructionText;
    state = state.copyWith(isTesting: true, clearTestResult: true);

    try {
      final now = DateTime.now().toUtc();
      final assembler = const ContextAssembler();
      final catalog = await ref.read(modelCatalogFutureProvider.future);
      final contextWindow = catalog.getModel(category).contextWindow;

      // 1. Before Run (Baseline without instructions)
      final beforeRequestId = 'trace_test_before_${now.millisecondsSinceEpoch}';
      final beforeManifest = assembler.assemble(
        manifestId: 'manifest_$beforeRequestId',
        requestId: beforeRequestId,
        category: category.id,
        catalogRevision: catalog.revision,
        contextWindow: contextWindow,
        activeInstruction: null,
        conversationHistory: const [],
        userPrompt: question,
      );

      final beforeWatch = Stopwatch()..start();
      final beforeAnswer = await _generateResponse(beforeManifest);
      beforeWatch.stop();

      final beforeTrace = RequestTrace(
        requestId: beforeRequestId,
        ownerId: ownerId,
        conversationId: 'test_before_after',
        modelCategory: category.id,
        assistantVersion: 1,
        layers: [
          TraceLayer(
            type: TraceLayerType.instruction,
            title: 'Инструкция',
            contentSnippet: 'Без инструкций (базовое поведение модели)',
            tokenCount: 0,
            location: LocationTag.onDevice,
          ),
          TraceLayer(
            type: TraceLayerType.userPrompt,
            title: 'Запрос пользователя',
            contentSnippet: question,
            tokenCount: beforeManifest.estimatedTokens,
            location: LocationTag.onDevice,
          ),
          TraceLayer(
            type: TraceLayerType.response,
            title: 'Ответ модели',
            contentSnippet: beforeAnswer,
            tokenCount: (beforeAnswer.length / 3.5).ceil(),
            location: LocationTag.craftAi,
          ),
        ],
        steps: const [
          TraceStep(
            stepIndex: 1,
            title: 'Сборка запроса',
            description: 'Инструкция отсутствует',
            location: LocationTag.onDevice,
          ),
          TraceStep(
            stepIndex: 2,
            title: 'Генерация ответа',
            description: 'Ответ базовой модели без правил',
            location: LocationTag.craftAi,
          ),
        ],
        usage: TraceUsage(
          promptTokens: beforeManifest.estimatedTokens,
          completionTokens: (beforeAnswer.length / 3.5).ceil(),
          totalTokens:
              beforeManifest.estimatedTokens +
              (beforeAnswer.length / 3.5).ceil(),
          durationMs: beforeWatch.elapsedMilliseconds,
          isServerReported: false,
          costTier: 2,
        ),
        status: TraceStatus.completed,
        createdAtUtc: now,
      );

      // 2. After Run (With draft instructions applied)
      final afterRequestId = 'trace_test_after_${now.millisecondsSinceEpoch}';
      final afterManifest = assembler.assemble(
        manifestId: 'manifest_$afterRequestId',
        requestId: afterRequestId,
        category: category.id,
        catalogRevision: catalog.revision,
        contextWindow: contextWindow,
        activeInstruction: activeInstruction.isNotEmpty
            ? activeInstruction
            : null,
        conversationHistory: const [],
        userPrompt: question,
      );

      final afterWatch = Stopwatch()..start();
      final afterAnswer = await _generateResponse(afterManifest);
      afterWatch.stop();

      final afterTrace = RequestTrace(
        requestId: afterRequestId,
        ownerId: ownerId,
        conversationId: 'test_before_after',
        modelCategory: category.id,
        assistantVersion: 1,
        layers: [
          TraceLayer(
            type: TraceLayerType.instruction,
            title: 'Активная инструкция',
            contentSnippet: activeInstruction.isNotEmpty
                ? activeInstruction
                : 'Инструкция пуста',
            tokenCount: (activeInstruction.length / 3.5).ceil(),
            location: LocationTag.onDevice,
          ),
          TraceLayer(
            type: TraceLayerType.userPrompt,
            title: 'Запрос пользователя',
            contentSnippet: question,
            tokenCount: afterManifest.estimatedTokens,
            location: LocationTag.onDevice,
          ),
          TraceLayer(
            type: TraceLayerType.response,
            title: 'Ответ модели',
            contentSnippet: afterAnswer,
            tokenCount: (afterAnswer.length / 3.5).ceil(),
            location: LocationTag.craftAi,
          ),
        ],
        steps: const [
          TraceStep(
            stepIndex: 1,
            title: 'Сборка запроса',
            description: 'Подстановка инструкций учителя',
            location: LocationTag.onDevice,
          ),
          TraceStep(
            stepIndex: 2,
            title: 'Генерация ответа',
            description: 'Ответ модели с учётом роли и ограничений',
            location: LocationTag.craftAi,
          ),
        ],
        usage: TraceUsage(
          promptTokens: afterManifest.estimatedTokens,
          completionTokens: (afterAnswer.length / 3.5).ceil(),
          totalTokens:
              afterManifest.estimatedTokens + (afterAnswer.length / 3.5).ceil(),
          durationMs: afterWatch.elapsedMilliseconds,
          isServerReported: false,
          costTier: 2,
        ),
        status: TraceStatus.completed,
        createdAtUtc: now.add(const Duration(milliseconds: 50)),
      );

      // 3. Save both traces via trace repository
      final traceRepo = ref.read(traceRepositoryProvider);
      await traceRepo.saveTrace(beforeTrace);
      await traceRepo.saveTrace(afterTrace);

      final result = TestComparisonResult(
        question: question,
        modelCategory: category.id,
        beforeAnswer: beforeAnswer,
        afterAnswer: afterAnswer,
        beforeTrace: beforeTrace,
        afterTrace: afterTrace,
        executedAtUtc: now,
      );

      state = state.copyWith(isTesting: false, testResult: result);

      return result;
    } catch (e) {
      state = state.copyWith(
        isTesting: false,
        errorMessage: 'Ошибка при выполнении теста: $e',
      );
      rethrow;
    }
  }

  Future<String> _generateResponse(ContextManifest manifest) async {
    final client = ref.read(chatStreamClientProvider);
    final answer = StringBuffer();
    var completed = false;
    await for (final event in client.streamCompletion(
      ownerId: ownerId,
      category: manifest.category,
      catalogRevision: manifest.catalogRevision,
      messages: manifest.messages,
      requestId: manifest.requestId,
    )) {
      if (event is TextDeltaStreamEvent) {
        answer.write(event.text);
      } else if (event is TerminalStreamEvent) {
        if (!event.isCompleted) {
          throw StateError(
            event.code ??
                '\u0413\u0435\u043d\u0435\u0440\u0430\u0446\u0438\u044f \u043f\u0440\u0435\u0440\u0432\u0430\u043d\u0430',
          );
        }
        completed = true;
        break;
      }
    }
    if (!completed || answer.toString().trim().isEmpty) {
      throw StateError(
        '\u041c\u043e\u0434\u0435\u043b\u044c \u043d\u0435 \u0432\u0435\u0440\u043d\u0443\u043b\u0430 \u043f\u043e\u043b\u043d\u044b\u0439 \u043e\u0442\u0432\u0435\u0442.',
      );
    }
    return answer.toString().trim();
  }

  /// Saves the draft instructions to persistent storage, activates skill, and commits assistant version (F11-07)
  Future<void> saveToAssistant({String? reason}) async {
    state = state.copyWith(isSaving: true, errorMessage: null);

    try {
      final repo = ref.read(instructionsRepositoryProvider);
      await repo.saveInstructionConfig(ownerId, state.config);

      final systemRules = state.config.toSystemRules();
      final actualReason = (reason != null && reason.trim().isNotEmpty)
          ? reason.trim()
          : (state.config.isRawMode
                ? 'Обновлен прямой текст инструкции'
                : 'Обновлены правила (${state.config.enabledRulesCount} активных)');

      final assistantController = ref.read(
        assistantControllerProvider(ownerId),
      );
      await assistantController.saveInstructions(
        systemRules: systemRules,
        reason: actualReason,
      );

      ref.invalidate(instructionConfigProvider(ownerId));
      ref.invalidate(assistantConfigProvider(ownerId));

      state = state.copyWith(isSaving: false);
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Не удалось сохранить инструкции: $e',
      );
      rethrow;
    }
  }
}

final instructionDraftProvider =
    NotifierProvider.family<
      InstructionDraftNotifier,
      InstructionDraftState,
      String
    >(InstructionDraftNotifier.new);
