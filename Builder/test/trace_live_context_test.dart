import 'package:builder/features/chat/domain/context_assembler.dart';
import 'package:builder/features/trace/domain/request_trace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Trace uses the sent context and server usage without fixture memory',
    () {
      final manifest = ContextManifest(
        id: 'manifest',
        requestId: 'request',
        category: 'fast',
        catalogRevision: 'revision',
        messages: const [
          {'role': 'system', 'content': 'Actual instruction'},
          {'role': 'user', 'content': 'Earlier question'},
          {'role': 'assistant', 'content': 'Earlier answer'},
          {'role': 'user', 'content': 'Current question'},
        ],
        estimatedTokens: 30,
        reservedTokens: 4096,
        assembledAtUtc: DateTime.utc(2026),
      );
      final trace = RequestTrace.fromExecution(
        requestId: 'request',
        ownerId: 'owner',
        conversationId: 'conversation',
        modelCategory: 'fast',
        modelId: 'actual-backend-model',
        assistantVersion: 1,
        userPrompt: 'Current question',
        responseText: 'Actual answer',
        durationMs: 250,
        status: TraceStatus.completed,
        manifest: manifest,
        serverPromptTokens: 42,
        serverCompletionTokens: 12,
        serverTotalTokens: 54,
      );
      expect(
        trace.layers
            .where((l) => l.type == TraceLayerType.instruction)
            .single
            .contentSnippet,
        'Actual instruction',
      );
      expect(
        trace.layers.where((l) => l.type == TraceLayerType.memory),
        isEmpty,
      );
      expect(
        trace.layers.where((l) => l.type == TraceLayerType.retrieval),
        isEmpty,
      );
      final history = trace.layers
          .where((l) => l.type == TraceLayerType.history)
          .single;
      expect(history.contentSnippet, contains('Earlier answer'));
      expect(history.contentSnippet, isNot(contains('Current question')));
      expect(trace.steps[3].title, contains('actual-backend-model'));
      expect(trace.usage.isServerReported, isTrue);
      expect(trace.usage.totalTokens, 54);
      expect(RequestTrace.fromJson(trace.toJson()).usage.promptTokens, 42);
    },
  );

  test(
    'Missing server usage stays an estimate and absent context stays absent',
    () {
      final manifest = const ContextAssembler().assemble(
        manifestId: 'manifest',
        requestId: 'request',
        category: 'fast',
        catalogRevision: 'revision',
        contextWindow: 128000,
        conversationHistory: [],
        userPrompt: 'Question',
      );
      final trace = RequestTrace.fromExecution(
        requestId: 'request',
        ownerId: 'owner',
        conversationId: 'conversation',
        modelCategory: 'fast',
        assistantVersion: 1,
        userPrompt: 'Question',
        responseText: '',
        durationMs: 10,
        status: TraceStatus.error,
        manifest: manifest,
      );
      expect(trace.usage.isServerReported, isFalse);
      expect(trace.usage.promptTokens, manifest.estimatedTokens);
      expect(
        trace.layers.where(
          (l) => [
            TraceLayerType.instruction,
            TraceLayerType.memory,
            TraceLayerType.retrieval,
            TraceLayerType.history,
          ].contains(l.type),
        ),
        isEmpty,
      );
    },
  );
}
