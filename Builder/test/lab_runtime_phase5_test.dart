import 'dart:async';

import 'package:builder/features/lab_runtime/domain/lab_run_models.dart';
import 'package:builder/features/lab_runtime/infrastructure/lab_runtime_api.dart';
import 'package:builder/features/lab_runtime/presentation/lab_agent_chat_page.dart';
import 'package:builder/features/lab_runtime/presentation/lab_agent_settings_page.dart';
import 'package:builder/features/lab_runtime/presentation/lab_run_controller.dart';
import 'package:builder/features/lab_runtime/presentation/lab_run_trace_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLabRuntimeApi implements LabRuntimeApi {
  final List<String> createRunIdempotencyKeys = [];
  int createRunCalls = 0;
  bool failCreateRun = false;
  Completer<LabRun>? pendingCreateRun;
  LabRun? nextRunResponse;
  LabRun? runByIdResponse;

  @override
  Future<LabRun> createRun({
    required String agentId,
    required String prompt,
    required String idempotencyKey,
    List<String> imageDataUris = const [],
  }) async {
    createRunCalls++;
    createRunIdempotencyKeys.add(idempotencyKey);
    if (pendingCreateRun != null) {
      return pendingCreateRun!.future;
    }
    if (failCreateRun) {
      throw const LabApiException(
        code: 'network.offline',
        message: 'Нет подключения к сети. Черновик сохранён локально.',
        isOffline: true,
      );
    }
    return nextRunResponse ??
        LabRun(
          id: 'run-1',
          agentId: agentId,
          agentVersionId: 'ver-1',
          epoch: 1,
          modelId: 'google/gemini-2.5-flash',
          status: 'completed',
          stopReason: 'completed',
          finalOutput: 'Готовый ответ.',
        );
  }

  @override
  Future<LabRun> getRun(String runId) async {
    return runByIdResponse ??
        LabRun(
          id: runId,
          agentId: 'agent-1',
          agentVersionId: 'ver-1',
          epoch: 1,
          modelId: 'google/gemini-2.5-flash',
          status: 'completed',
          stopReason: 'completed',
          finalOutput: 'Ответ',
          events: const [
            LabRunEvent(
              id: 'e1',
              sequence: 1,
              epoch: 1,
              eventType: 'tool_result',
              payload: {
                'tool_name': 'save_material',
                'result': {'material_id': 'mat-999'},
              },
              createdAtUtc: '2026-11-15T12:00:00Z',
            ),
          ],
        );
  }

  @override
  Future<LabRun> cancelRun(String runId) async =>
      LabRun(
        id: runId,
        agentId: 'agent-1',
        agentVersionId: 'ver-1',
        epoch: 1,
        modelId: 'google/gemini-2.5-flash',
        status: 'cancelled',
        stopReason: 'cancelled',
      );

  @override
  Future<LabRun> resolveAction({
    required String runId,
    required String actionId,
    required String decision,
    Map<String, dynamic>? params,
  }) async =>
      LabRun(
        id: runId,
        agentId: 'agent-1',
        agentVersionId: 'ver-1',
        epoch: 1,
        modelId: 'google/gemini-2.5-flash',
        status: 'completed',
        stopReason: 'completed',
        finalOutput: 'Сохранено.',
      );

  @override
  Future<List<LabMaterialItem>> listMaterials(String agentId) async => const [];

  @override
  Future<LabMaterialItem> createMaterial({
    required String agentId,
    required String title,
    required String content,
    String source = 'text',
  }) async =>
      LabMaterialItem(
        id: 'm1',
        agentId: agentId,
        title: title,
        content: content,
        source: source,
        createdAtUtc: '',
      );

  @override
  Future<void> deleteMaterial({
    required String agentId,
    required String materialId,
  }) async {}

  @override
  Future<LabPhotoExtraction> uploadPhoto({
    required String agentId,
    required String fileName,
    required List<int> bytes,
  }) async =>
      const LabPhotoExtraction(
        photoId: 'p1',
        extractedText: 'Текст с фото',
        expiresAtUtc: '',
      );

  @override
  Future<List<LabMemoryItem>> listMemory(String agentId) async => const [];

  @override
  Future<LabMemoryItem> createMemory({
    required String agentId,
    required String content,
  }) async =>
      LabMemoryItem(
        id: 'mem-1',
        agentId: agentId,
        content: content,
        createdAtUtc: '',
      );

  @override
  Future<void> deleteMemory({
    required String agentId,
    required String entryId,
  }) async {}

  @override
  Future<List<LabSkillItem>> listSkills(String agentId) async => const [];

  @override
  Future<LabSkillItem> updateSkill({
    required String agentId,
    required String slug,
    required bool enabled,
    required String overrideText,
    required bool allowSave,
    required bool allowSearch,
  }) async =>
      LabSkillItem(
        slug: slug,
        title: slug,
        version: '1.0.0',
        baseContent: '',
        enabled: enabled,
        overrideText: overrideText,
        revision: 1,
      );
}

void main() {
  testWidgets('double-tap Retry sends single Idempotency-Key', (tester) async {
    final api = FakeLabRuntimeApi()..failCreateRun = true;
    final controller = LabRunController(
      api: api,
      config: const LabAgentRunConfig(
        agentId: 'agent-1',
        model: LabModelInfo(
          modelId: 'google/gemini-2.5-flash',
          supportsTools: true,
          supportsVision: true,
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LabAgentChatPage(
            agentName: 'Агент 1',
            controller: controller,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Составь тест');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('Повторить'), findsOneWidget);
    expect(api.createRunIdempotencyKeys.length, 1);

    // Double tap retry while a slow request is in flight
    api.failCreateRun = false;
    api.pendingCreateRun = Completer<LabRun>();
    await tester.tap(find.text('Повторить'));
    await tester.tap(find.text('Повторить'));
    await tester.pump();

    expect(api.createRunIdempotencyKeys.length, 2);
    expect(
      api.createRunIdempotencyKeys[0],
      equals(api.createRunIdempotencyKeys[1]),
    );

    api.pendingCreateRun!.complete(
      const LabRun(
        id: 'run-1',
        agentId: 'agent-1',
        agentVersionId: 'ver-1',
        epoch: 1,
        modelId: 'google/gemini-2.5-flash',
        status: 'completed',
        stopReason: 'completed',
        finalOutput: 'Тест готов.',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Тест готов.'), findsOneWidget);
  });

  testWidgets('camera permission denial preserves material draft', (tester) async {
    final api = FakeLabRuntimeApi();

    await tester.pumpWidget(
      MaterialApp(
        home: LabAgentSettingsPage(
          agentId: 'agent-1',
          api: api,
          availableModels: const [
            LabModelInfo(modelId: 'google/gemini-2.5-flash', supportsTools: true, supportsVision: true),
          ],
          initialModelId: 'google/gemini-2.5-flash',
          initialInstruction: 'Инструкция',
          initialAllowSave: true,
          initialAllowSearch: true,
          photoPicker: () async {
            throw const LabPhotoPermissionDeniedException();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll to material section and enter draft text
    final listScrollable = find.byType(Scrollable).first;
    final contentField = find.byKey(const Key('material_content_field'));
    await tester.scrollUntilVisible(contentField, 300, scrollable: listScrollable);
    await tester.enterText(contentField, 'Мой черновик материала');
    await tester.pump();

    // Trigger photo extraction -> permission denied
    await tester.scrollUntilVisible(
      find.text('Извлечь с фото'),
      200,
      scrollable: listScrollable,
    );
    await tester.tap(find.text('Извлечь с фото'));
    await tester.pumpAndSettle();

    expect(find.text('Мой черновик материала'), findsOneWidget);
    expect(
      find.text('Доступ к камере или фото отклонён. Черновик сохранён.'),
      findsOneWidget,
    );
  });

  testWidgets('incompatible model blocks send before API call', (tester) async {
    final api = FakeLabRuntimeApi();
    final controller = LabRunController(
      api: api,
      config: const LabAgentRunConfig(
        agentId: 'agent-1',
        model: LabModelInfo(
          modelId: 'text-only',
          supportsTools: false,
          supportsVision: false,
        ),
        allowSave: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LabAgentChatPage(
            agentName: 'Агент 1',
            controller: controller,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Сохрани урок');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(api.createRunCalls, 0);
    expect(find.text('Модель несовместима'), findsOneWidget);
  });

  testWidgets('tool error is not shown as clean success and trace shows material_id', (tester) async {
    final api = FakeLabRuntimeApi()
      ..nextRunResponse = const LabRun(
        id: 'run-err',
        agentId: 'agent-1',
        agentVersionId: 'ver-1',
        epoch: 1,
        modelId: 'google/gemini-2.5-flash',
        status: 'completed',
        stopReason: 'completed',
        finalOutput: 'Ответ модели.',
        events: [
          LabRunEvent(
            id: 'e-rej',
            sequence: 1,
            epoch: 1,
            eventType: 'tool_rejected',
            payload: {'tool_name': 'save_material', 'reason': 'permission_denied'},
            createdAtUtc: '',
          ),
        ],
      );

    final controller = LabRunController(
      api: api,
      config: const LabAgentRunConfig(
        agentId: 'agent-1',
        model: LabModelInfo(
          modelId: 'google/gemini-2.5-flash',
          supportsTools: true,
          supportsVision: true,
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LabAgentChatPage(
            agentName: 'Агент 1',
            controller: controller,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Проверь');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('Инструмент завершился с ошибкой'), findsOneWidget);

    // Open trace page
    await tester.pumpWidget(
      MaterialApp(
        home: LabRunTracePage(runId: 'run-1', api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ID материала: mat-999'), findsOneWidget);
  });
}
