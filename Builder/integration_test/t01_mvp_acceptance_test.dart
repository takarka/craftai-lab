import 'package:builder/features/course/lab_course_mvp.dart';
import 'package:builder/features/lab_runtime/domain/lab_run_models.dart';
import 'package:builder/features/lab_runtime/infrastructure/lab_runtime_api.dart';
import 'package:builder/features/lab_runtime/presentation/lab_agent_chat_page.dart';
import 'package:builder/features/lab_runtime/presentation/lab_run_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _T01RuntimeApi extends LabRuntimeApi {
  final Map<String, LabMaterialItem> materials = {};
  final Map<String, LabMemoryItem> memory = {};

  @override
  Future<List<LabModelInfo>> listModels() async => const [
    LabModelInfo(
      modelId: 'google/gemini-2.5-flash',
      available: true,
      supportsTools: true,
      supportsVision: true,
    ),
    LabModelInfo(
      modelId: 'qwen/qwen-2.5-72b-instruct',
      available: true,
      supportsTools: true,
      supportsVision: false,
    ),
  ];

  @override
  Future<LabRun> createRun({
    required String agentId,
    required String prompt,
    required String idempotencyKey,
    List<String> imageDataUris = const [],
  }) async {
    if (prompt.contains('Сохрани')) {
      return LabRun(
        id: 'run-save',
        agentId: agentId,
        agentVersionId: 'v1',
        epoch: 0,
        modelId: 'google/gemini-2.5-flash',
        status: 'awaiting_confirmation',
        toolCallsCount: 1,
        pendingActions: const [
          LabPendingAction(
            id: 'act-1',
            toolCallId: 'tc-1',
            toolName: 'save_material',
            params: {'title': 'Испарение', 'content': 'Переход жидкости в газ'},
            paramsHash: 'h1',
            status: 'pending',
            expiresAtUtc: '2026-11-16T12:00:00Z',
          ),
        ],
      );
    }
    return LabRun(
      id: 'run-q',
      agentId: agentId,
      agentVersionId: 'v1',
      epoch: 0,
      modelId: 'google/gemini-2.5-flash',
      status: 'completed',
      stopReason: 'completed',
      finalOutput:
          '1. Что такое испарение?\n2. Где оно происходит?\n3. Как влияет нагревание?',
    );
  }

  @override
  Future<LabRun> resolveAction({
    required String runId,
    required String actionId,
    required String decision,
    Map<String, dynamic>? params,
  }) async {
    if (decision == 'approve') {
      materials['mat-evap-1'] = const LabMaterialItem(
        id: 'mat-evap-1',
        agentId: 'agent-1',
        title: 'Испарение',
        content: 'Переход жидкости в газ',
        source: 'text',
        createdAtUtc: '2026-11-16T00:00:00Z',
      );
    }
    return const LabRun(
      id: 'run-save',
      agentId: 'agent-1',
      agentVersionId: 'v1',
      epoch: 0,
      modelId: 'google/gemini-2.5-flash',
      status: 'completed',
      stopReason: 'completed',
      finalOutput: 'Материал «Испарение» сохранён (ID: mat-evap-1).',
      events: [
        LabRunEvent(
          id: 'evt-1',
          sequence: 1,
          epoch: 0,
          eventType: 'tool_result',
          payload: {
            'tool_name': 'save_material',
            'result': {'material_id': 'mat-evap-1'},
          },
          createdAtUtc: '2026-11-16T00:00:00Z',
        ),
      ],
    );
  }

  @override
  Future<LabRun> getRun(String runId) async => const LabRun(
    id: 'run-save',
    agentId: 'agent-1',
    agentVersionId: 'v1',
    epoch: 0,
    modelId: 'google/gemini-2.5-flash',
    status: 'completed',
    stopReason: 'completed',
    finalOutput: 'Материал «Испарение» сохранён (ID: mat-evap-1).',
    events: [
      LabRunEvent(
        id: 'evt-1',
        sequence: 1,
        epoch: 0,
        eventType: 'tool_result',
        payload: {
          'tool_name': 'save_material',
          'result': {'material_id': 'mat-evap-1'},
        },
        createdAtUtc: '2026-11-16T00:00:00Z',
      ),
    ],
  );

  @override
  Future<LabRun> cancelRun(String runId) async => throw UnimplementedError();
  @override
  Future<List<LabMaterialItem>> listMaterials(String agentId) async =>
      materials.values.toList();
  @override
  Future<LabMaterialItem> createMaterial({
    required String agentId,
    required String title,
    required String content,
    String source = 'text',
  }) async => throw UnimplementedError();
  @override
  Future<void> deleteMaterial({
    required String agentId,
    required String materialId,
  }) async => materials.remove(materialId);
  @override
  Future<LabPhotoExtraction> uploadPhoto({
    required String agentId,
    required String fileName,
    required List<int> bytes,
  }) async => throw UnimplementedError();
  @override
  Future<List<LabMemoryItem>> listMemory(String agentId) async =>
      memory.values.toList();
  @override
  Future<LabMemoryItem> createMemory({
    required String agentId,
    required String content,
  }) async => throw UnimplementedError();
  @override
  Future<void> deleteMemory({
    required String agentId,
    required String entryId,
  }) async => memory.remove(entryId);
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
  }) async => throw UnimplementedError();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T01: Teacher builds agent, confirms MCP save, and views trace', (
    tester,
  ) async {
    final api = _T01RuntimeApi();
    final controller = LabRunController(
      api: api,
      config: const LabAgentRunConfig(
        agentId: 'agent-1',
        model: LabModelInfo(
          modelId: 'google/gemini-2.5-flash',
          available: true,
          supportsTools: true,
          supportsVision: true,
        ),
        allowSave: true,
        allowSearch: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LabAgentChatPage(
            agentName: 'Естествознание 5',
            controller: controller,
          ),
        ),
      ),
    );

    // Step 4: Generate 3 questions
    await tester.enterText(
      find.byKey(const Key('lab_chat_prompt_field')),
      'Подготовь вопросы по материалу',
    );
    await tester.tap(find.byKey(const Key('lab_chat_send_btn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1. Что такое испарение?'), findsOneWidget);

    // Step 5: Save material via MCP with confirmation
    await tester.enterText(
      find.byKey(const Key('lab_chat_prompt_field')),
      'Сохрани фрагмент Испарение',
    );
    await tester.tap(find.byKey(const Key('lab_chat_send_btn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Требуется подтверждение'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lab_confirm_approve_btn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('mat-evap-1'), findsOneWidget);
    expect(api.materials.containsKey('mat-evap-1'), isTrue);

    // Verify 7 lessons catalog
    expect(LabCourseCatalog.lessons.length, 7);
  });
}
