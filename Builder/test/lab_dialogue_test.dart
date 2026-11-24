import 'dart:convert';

import 'package:builder/features/lab_runtime/domain/lab_run_models.dart';
import 'package:builder/features/lab_runtime/infrastructure/lab_runtime_api.dart';
import 'package:builder/features/lab_runtime/presentation/lab_agent_chat_page.dart';
import 'package:builder/features/lab_runtime/presentation/lab_run_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('dialogue restores and appends turns instead of toggling outputs', (
    tester,
  ) async {
    final requests = <http.Request>[];
    Map<String, dynamic> run(String id, String answer) => {
      'id': id,
      'agent_id': 'science',
      'status': 'completed',
      'final_output': answer,
    };
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'conversation_id': 'conversation-a',
            'turns': [
              {
                'prompt': 'Учитывай пятый класс.',
                'run': run('one', 'Пятый класс, понял.'),
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode(run('two', 'Два вопроса для пятого класса.')),
        201,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final api = HttpLabRuntimeApi(
      client: client,
      baseUri: Uri.parse('https://example.test'),
      getAccessToken: () async => null,
    );
    final controller = LabRunController(
      api: api,
      config: const LabAgentRunConfig(
        agentId: 'science',
        useDialogue: true,
        model: LabModelInfo(
          modelId: 'selected',
          available: true,
          supportsTools: true,
          supportsVision: false,
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LabAgentChatPage(agentName: 'Урок', controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder bubble(String value) => find.byWidgetPredicate(
      (widget) => widget is SelectableText && widget.data == value,
    );
    expect(bubble('Учитывай пятый класс.'), findsOneWidget);
    expect(bubble('Пятый класс, понял.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Теперь про испарение.');
    await tester.tap(find.byTooltip('Отправить'));
    await tester.pumpAndSettle();
    expect(bubble('Учитывай пятый класс.'), findsOneWidget);
    expect(bubble('Теперь про испарение.'), findsOneWidget);
    expect(bubble('Два вопроса для пятого класса.'), findsOneWidget);
    expect(find.text('Показать «до»'), findsNothing);
    final sent = requests.singleWhere((r) => r.method == 'POST');
    expect(jsonDecode(sent.body), containsPair('conversation_id', 'conversation-a'));
    expect(jsonDecode(sent.body), containsPair('dialogue', true));
    expect(sent.headers['Idempotency-Key'], isNotEmpty);
  });
}
