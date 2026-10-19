import '../infrastructure/calendar_adapter.dart';
import '../infrastructure/notes_adapter.dart';
import '../infrastructure/search_adapter.dart';
import 'pending_action.dart';
import 'tool_definition.dart';
import 'tool_invocation.dart';
import 'tools_registry.dart';
import 'tools_repository.dart';

/// Result of dispatching or executing a tool (F14-01, F14-05).
class ToolExecutionResult {
  final bool success;
  final String toolName;
  final Map<String, dynamic>? data;
  final String? errorMessage;
  final String? errorCode;
  final PendingAction? pendingAction;

  const ToolExecutionResult({
    required this.success,
    required this.toolName,
    this.data,
    this.errorMessage,
    this.errorCode,
    this.pendingAction,
  });

  bool get requiresConfirmation => pendingAction != null;

  factory ToolExecutionResult.completed({
    required String toolName,
    required Map<String, dynamic> data,
  }) {
    return ToolExecutionResult(success: true, toolName: toolName, data: data);
  }

  factory ToolExecutionResult.needsConfirmation({
    required String toolName,
    required PendingAction pendingAction,
  }) {
    return ToolExecutionResult(
      success: true,
      toolName: toolName,
      pendingAction: pendingAction,
    );
  }

  factory ToolExecutionResult.failure({
    required String toolName,
    required String errorMessage,
    String? errorCode,
  }) {
    return ToolExecutionResult(
      success: false,
      toolName: toolName,
      errorMessage: errorMessage,
      errorCode: errorCode,
    );
  }
}

/// Central dispatcher for executing tools with grant verification, OS permission check,
/// and confirmation state machine enforcement (F14-01, F14-05, F14-10, F14-11, F14-12).
class ToolsDispatcher {
  final ToolsRepository repository;
  final CalendarAdapter calendarAdapter;
  final NotesAdapter notesAdapter;
  final SearchAdapter searchAdapter;
  final PendingActionStateMachine stateMachine;

  ToolsDispatcher({
    required this.repository,
    CalendarAdapter? calendarAdapter,
    NotesAdapter? notesAdapter,
    SearchAdapter? searchAdapter,
    PendingActionStateMachine? stateMachine,
  }) : calendarAdapter = calendarAdapter ?? CalendarAdapter(),
       notesAdapter = notesAdapter ?? NotesAdapter(),
       searchAdapter = searchAdapter ?? const SearchAdapter(),
       stateMachine = stateMachine ?? const PendingActionStateMachine();

  /// Dispatches a tool call from LLM or UI.
  Future<ToolExecutionResult> dispatch({
    required String ownerId,
    required String toolName,
    required Map<String, dynamic> args,
    String invocationSource = 'assistant_chat',
  }) async {
    final startTime = DateTime.now().toUtc();
    final tool = ToolsRegistry.getByName(toolName);
    if (tool == null) {
      return ToolExecutionResult.failure(
        toolName: toolName,
        errorMessage: 'Инструмент «$toolName» не зарегистрирован в системе',
        errorCode: 'TOOL_NOT_FOUND',
      );
    }

    // 1. Schema Validation (F14-01)
    final validationErrors = tool.validateArguments(args);
    if (validationErrors.isNotEmpty) {
      return ToolExecutionResult.failure(
        toolName: toolName,
        errorMessage:
            'Ошибка валидации параметров: ${validationErrors.join(', ')}',
        errorCode: 'INVALID_ARGUMENTS',
      );
    }

    // 2. Runtime Grant Check (F14-10: check grant before execution)
    final grant = await repository.getGrant(ownerId, toolName);
    if (grant == null || !grant.isEnabled) {
      return ToolExecutionResult.failure(
        toolName: toolName,
        errorMessage:
            'Инструмент «${tool.displayName}» отключён в настройках ассистента',
        errorCode: 'TOOL_DISABLED',
      );
    }

    // 3. OS Permission Check (F14-02, F14-04)
    final osPerm = await repository.getOsPermission(toolName);
    if (osPerm == OsPermissionStatus.denied) {
      return ToolExecutionResult.failure(
        toolName: toolName,
        errorMessage:
            'Отсутствует системное разрешение устройства для «${tool.displayName}»',
        errorCode: 'PERMISSION_DENIED',
      );
    }

    // 4. Confirmation requirement check (F14-05)
    if (tool.requiresConfirmation) {
      final now = DateTime.now().toUtc();
      final invocationId =
          'act_${now.millisecondsSinceEpoch}_${toolName.hashCode.abs() % 1000}';
      final paramsHash = PendingAction.computeParamsHash(args);

      final action = PendingAction(
        invocationId: invocationId,
        ownerId: ownerId,
        workspaceEpoch: 1,
        actionName: toolName,
        paramsHash: paramsHash,
        params: args,
        status: PendingActionStatus.pending,
        expiresAtUtc: now.add(const Duration(minutes: 15)),
        createdAtUtc: now,
      );

      await repository.createPendingAction(action);
      return ToolExecutionResult.needsConfirmation(
        toolName: toolName,
        pendingAction: action,
      );
    }

    // 5. Direct Execution for read-only tools
    try {
      final data = await _executeToolImplementation(ownerId, toolName, args);
      final completedTime = DateTime.now().toUtc();

      // Log invocation (F14-11)
      await repository.logInvocation(
        ToolInvocationRecord(
          id: 'inv_${startTime.millisecondsSinceEpoch}',
          ownerId: ownerId,
          toolName: toolName,
          invocationSource: invocationSource,
          args: args,
          result: data,
          startedAtUtc: startTime,
          completedAtUtc: completedTime,
        ),
      );

      return ToolExecutionResult.completed(toolName: toolName, data: data);
    } catch (e) {
      return ToolExecutionResult.failure(
        toolName: toolName,
        errorMessage: 'Ошибка выполнения инструмента: $e',
        errorCode: 'EXECUTION_ERROR',
      );
    }
  }

  /// Confirms and executes a pending action via domain state machine (F14-05, F14-12).
  Future<ToolExecutionResult> confirmAndExecutePendingAction({
    required String ownerId,
    required String invocationId,
  }) async {
    final action = await repository.getPendingAction(invocationId);
    if (action == null) {
      return ToolExecutionResult.failure(
        toolName: 'unknown',
        errorMessage: 'Карточка подтверждения не найдена',
        errorCode: 'ACTION_NOT_FOUND',
      );
    }

    // Verify owner
    if (action.ownerId != ownerId) {
      return ToolExecutionResult.failure(
        toolName: action.actionName,
        errorMessage: 'Доступ запрещён к чужому действию',
        errorCode: 'ACCESS_DENIED',
      );
    }

    // State machine check & transitions (F14-12: double tap guard)
    if (ToolsRegistry.getByName(action.actionName) == null) {
      return ToolExecutionResult.failure(
        toolName: action.actionName,
        errorMessage: 'Инструмент больше не доступен',
        errorCode: 'TOOL_NOT_FOUND',
      );
    }
    try {
      final approved = stateMachine.approve(action);
      await repository.updatePendingActionStatus(
        invocationId: invocationId,
        status: approved.status,
      );

      final startTime = DateTime.now().toUtc();
      final data = await _executeToolImplementation(
        ownerId,
        action.actionName,
        action.params,
      );
      final completedTime = DateTime.now().toUtc();

      final executed = stateMachine.markExecuted(approved);
      await repository.updatePendingActionStatus(
        invocationId: invocationId,
        status: executed.status,
      );

      // Log invocation (F14-11)
      await repository.logInvocation(
        ToolInvocationRecord(
          id: 'inv_${startTime.millisecondsSinceEpoch}',
          ownerId: ownerId,
          toolName: action.actionName,
          args: action.params,
          result: data,
          startedAtUtc: startTime,
          completedAtUtc: completedTime,
          executionId: invocationId,
        ),
      );

      return ToolExecutionResult.completed(
        toolName: action.actionName,
        data: data,
      );
    } catch (e) {
      return ToolExecutionResult.failure(
        toolName: action.actionName,
        errorMessage: '$e',
        errorCode: 'STATE_TRANSITION_ERROR',
      );
    }
  }

  /// Rejects a pending action (F14-05, F14-12).
  Future<void> rejectPendingAction({
    required String ownerId,
    required String invocationId,
  }) async {
    final action = await repository.getPendingAction(invocationId);
    if (action == null || action.ownerId != ownerId) return;

    final rejected = stateMachine.reject(action);
    await repository.updatePendingActionStatus(
      invocationId: invocationId,
      status: rejected.status,
    );
  }

  Future<Map<String, dynamic>> _executeToolImplementation(
    String ownerId,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    switch (toolName) {
      case ToolsRegistry.readCalendar:
        final start = DateTime.parse(args['start_date'] as String);
        final end = DateTime.parse(args['end_date'] as String);
        final events = await calendarAdapter.readEvents(
          startDate: start,
          endDate: end,
        );
        return {
          'events': events.map((e) => e.toMap()).toList(),
          'count': events.length,
        };

      case ToolsRegistry.createCalendarEvent:
        final title = args['title'] as String;
        final start = DateTime.parse(args['start_time'] as String);
        final end = DateTime.parse(args['end_time'] as String);
        final isAllDay = args['is_all_day'] as bool? ?? false;
        final location = args['location'] as String?;
        final notes = args['notes'] as String?;
        final event = await calendarAdapter.createEvent(
          title: title,
          startTime: start,
          endTime: end,
          isAllDay: isAllDay,
          location: location,
          notes: notes,
        );
        return {
          'created_event': event.toMap(),
          'message': 'Событие «$title» успешно добавлено в календарь',
        };

      case ToolsRegistry.createNote:
        final title = args['title'] as String;
        final content = args['content'] as String;
        final note = await notesAdapter.createNote(
          ownerId: ownerId,
          title: title,
          content: content,
        );
        return {
          'created_note': note.toMap(),
          'message': 'Заметка «$title» сохранена',
        };

      case ToolsRegistry.readNotes:
        final query = args['query'] as String?;
        final notes = await notesAdapter.listNotes(ownerId, query: query);
        return {
          'notes': notes.map((n) => n.toMap()).toList(),
          'count': notes.length,
        };

      case ToolsRegistry.deleteNote:
        final noteId = args['note_id'] as String;
        final deleted = await notesAdapter.deleteNote(
          ownerId: ownerId,
          noteId: noteId,
        );
        return {'deleted': deleted, 'note_id': noteId};

      case ToolsRegistry.webSearch:
        final query = args['query'] as String;
        final hits = await searchAdapter.search(query);
        return {
          'query': query,
          'results': hits.map((h) => h.toMap()).toList(),
          'count': hits.length,
        };

      default:
        throw UnimplementedError('Обработчик для $toolName не реализован');
    }
  }
}
