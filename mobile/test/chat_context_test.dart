import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:mobile/models/chat_message.dart';
import 'package:mobile/services/chat_context.dart';
import 'package:mobile/ui/widgets/chat_bubble.dart';

ChatMessage message(
  String id,
  String text, {
  bool user = false,
  String reasoning = '',
  String? error,
  String? contextText,
  bool generating = false,
}) => ChatMessage(
  id: id,
  text: text,
  isUser: user,
  timestamp: DateTime(2026),
  reasoning: reasoning,
  error: error,
  contextText: contextText,
  isGenerating: generating,
);

class _UnusedEngine implements LlamaEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('restores history and system instruction in a new model session', () {
    final messages = [
      message('1', 'Remember my name', user: true),
      message('2', 'I remember', reasoning: 'Internal reasoning'),
    ];
    final oldSession = createChatSession(
      _UnusedEngine(),
      messages,
      systemPrompt: 'Answer in Russian',
    );
    oldSession.reset();
    final switchedSession = createChatSession(
      _UnusedEngine(),
      messages,
      systemPrompt: 'Answer in Russian',
    );
    expect(switchedSession.systemPrompt, 'Answer in Russian');
    expect(switchedSession.history.map((m) => m.content), [
      'Remember my name',
      'I remember',
    ]);
    expect(switchedSession.history.last.reasoning, isNull);
    final cleared = createChatSession(
      _UnusedEngine(),
      [],
      systemPrompt: 'Answer in Russian',
    );
    expect(cleared.history, isEmpty);
    expect(cleared.systemPrompt, 'Answer in Russian');
  });
  test('rebuilds dialogue for a new model without reasoning or errors', () {
    final messages = [
      message('1', 'Меня зовут Арка', user: true),
      message('2', 'Привет, Арка!', reasoning: 'private thought'),
      message('3', 'Продолжи', user: true),
      message('4', 'Частичный ответ', error: 'backend error'),
    ];
    final first = buildChatContext(messages);
    expect(first.map((m) => m.content), [
      'Меня зовут Арка',
      'Привет, Арка!',
      'Продолжи',
      'Частичный ответ',
    ]);
    expect(first.map((m) => m.role), [
      LlamaChatRole.user,
      LlamaChatRole.assistant,
      LlamaChatRole.user,
      LlamaChatRole.assistant,
    ]);
    expect(first.every((m) => m.reasoning == null), isTrue);
  });

  test('omits failed and unfinished turns and keeps later valid dialogue', () {
    final context = buildChatContext([
      message('1', 'Failed request', user: true),
      message('2', '', reasoning: 'thought only', error: 'failed'),
      message('3', 'Successful request', user: true),
      message('4', 'Answer'),
      message('5', 'Current request', user: true),
      message('6', 'Partial', generating: true),
    ]);
    expect(context.map((m) => m.content), ['Successful request', 'Answer']);
    expect(buildChatContext([]), isEmpty);
  });

  test('preserves web context while keeping visible user text separate', () {
    final user = message(
      '1',
      'Question',
      user: true,
      contextText: 'Search results and question',
    );
    expect(
      buildChatContext([user, message('2', 'Answer')]).first.content,
      'Search results and question',
    );
    expect(user.text, 'Question');
    expect(
      message(
        '3',
        'Answer',
        reasoning: 'Thinking',
      ).copyWith(text: 'Updated').reasoning,
      'Thinking',
    );
  });

  testWidgets('shows separate reasoning and final answer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(
            message: message(
              '1',
              'Final answer',
              reasoning: 'Reasoning details',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Рассуждение модели'), findsOneWidget);
    expect(find.text('Final answer'), findsOneWidget);
    expect(find.text('Reasoning details'), findsNothing);
    await tester.tap(find.text('Рассуждение модели'));
    await tester.pump();
    expect(find.text('Reasoning details'), findsOneWidget);
  });

  testWidgets('shows reasoning while the answer is still generating', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(
            message: message(
              '1',
              '',
              reasoning: 'Live reasoning',
              generating: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Обдумываю ответ...'), findsOneWidget);
    expect(find.text('Live reasoning'), findsOneWidget);
    expect(find.text('Генерирую ответ...'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
