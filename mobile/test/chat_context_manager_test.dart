import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:mobile/models/chat_conversation.dart';
import 'package:mobile/models/chat_message.dart';
import 'package:mobile/services/chat_context.dart';
import 'package:mobile/services/chat_context_manager.dart';

class FakeContextEngine implements LlamaEngine {
  final List<List<LlamaChatMessage>> summaryRequests = [];
  final List<List<LlamaChatMessage>> countedRequests = [];
  bool cancelDuringSummary = false;
  bool cancelled = false;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #chatTemplate) {
      final messages =
          invocation.positionalArguments.first as List<LlamaChatMessage>;
      countedRequests.add(messages);
      final summarizing = messages.first.content.contains('до 150 слов');
      final tokens = summarizing
          ? 100
          : 40 +
                (messages.first.content.contains('Краткое содержание')
                    ? 30
                    : 0) +
                messages
                    .skip(1)
                    .fold<int>(0, (sum, m) => sum + m.content.length);
      return Future.value(
        LlamaChatTemplateResult(prompt: 'rendered', tokenCount: tokens),
      );
    }
    if (invocation.memberName == #create) {
      summaryRequests.add(
        invocation.positionalArguments.first as List<LlamaChatMessage>,
      );
      if (cancelDuringSummary) cancelled = true;
      return Stream.value(
        LlamaCompletionChunk.fromJson({
          'id': 'test',
          'object': 'chat.completion.chunk',
          'created': 0,
          'model': 'fake',
          'choices': [
            {
              'index': 0,
              'delta': {'content': 'Пользователь Арка.'},
            },
          ],
        }),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

ChatConversation conversation(int turns) => ChatConversation(
  id: 'chat',
  updatedAt: DateTime(2026),
  messages: [
    for (var i = 0; i < turns; i++) ...[
      ChatMessage(
        id: 'u$i',
        text: List.filled(200, 'q').join(),
        isUser: true,
        timestamp: DateTime(2026),
      ),
      ChatMessage(
        id: 'a$i',
        text: List.filled(200, 'a').join(),
        reasoning: 'Excluded reasoning',
        isUser: false,
        timestamp: DateTime(2026),
      ),
    ],
  ],
);

void main() {
  test('short history keeps all turns and reserves output space', () async {
    final engine = FakeContextEngine();
    final prepared = await ChatContextManager(engine).prepare(
      conversation: conversation(1),
      systemPrompt: 'System',
      userPrompt: 'Next',
      contextSize: 1024,
      thinking: false,
      cancelled: () => false,
      onSummary: (_, _) => fail('Short history must not be summarized'),
      onStatus: (_) {},
    );
    expect(prepared.promptTokens, 444);
    expect(prepared.responseTokens, 512);
    expect(engine.summaryRequests, isEmpty);
  });

  test(
    'summarizes oldest complete turn, retaining newest and current prompt',
    () async {
      final engine = FakeContextEngine();
      final original = conversation(2);
      var updated = original;
      final prepared = await ChatContextManager(engine).prepare(
        conversation: original,
        systemPrompt: 'System',
        userPrompt: 'Next',
        contextSize: 1024,
        thinking: true,
        cancelled: () => false,
        onSummary: (summary, id) => updated = updated.withSummary(summary, id),
        onStatus: (_) {},
      );
      expect(prepared.promptTokens, lessThanOrEqualTo(512));
      expect(updated.summarizedThroughId, 'a0');
      expect(updated.messages.length, 4);
      expect(updated.summary, 'Пользователь Арка.');
      expect(
        engine.summaryRequests.single.last.content,
        isNot(contains('Excluded reasoning')),
      );
      final nextContext = buildChatContext(
        updated.messages,
        afterId: updated.summarizedThroughId,
      );
      expect(nextContext.length, 2);
      final counted = engine.countedRequests.last;
      expect(counted.first.content, contains('Пользователь Арка.'));
      expect(counted.last.content, 'Next');
    },
  );

  test('cancellation prevents summary from being committed', () async {
    final engine = FakeContextEngine()..cancelDuringSummary = true;
    await expectLater(
      ChatContextManager(engine).prepare(
        conversation: conversation(2),
        systemPrompt: 'System',
        userPrompt: 'Next',
        contextSize: 1024,
        thinking: false,
        cancelled: () => engine.cancelled,
        onSummary: (_, _) => fail('Cancelled summary must not be saved'),
        onStatus: (_) {},
      ),
      throwsA(isA<ContextPreparationCancelled>()),
    );
  });

  test(
    'oversized current prompt fails instead of dropping the newest turn',
    () async {
      final engine = FakeContextEngine();
      await expectLater(
        ChatContextManager(engine).prepare(
          conversation: conversation(1),
          systemPrompt: 'System',
          userPrompt: List.filled(600, 'x').join(),
          contextSize: 1024,
          thinking: false,
          cancelled: () => false,
          onSummary: (_, _) => fail('Newest turn must be kept'),
          onStatus: (_) {},
        ),
        throwsStateError,
      );
    },
  );
}
