import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../session/session_repository.dart';
import '../../tools/domain/tools_dispatcher.dart';
import '../../tools/domain/tools_registry.dart';
import '../../tools/presentation/tools_providers.dart';
import '../domain/mcp_models.dart';
import '../infrastructure/mcp_client.dart';

/// Provider for McpClient configured with the active session token (F15-03, F15-04).
final mcpClientProvider = Provider<McpClient>((ref) {
  final session = ref.watch(sessionProvider).asData?.value;
  return McpClient(
    sessionTokenProvider: () => session is AuthenticatedSession
        ? 'craftai_auth_token_${session.ownerId}'
        : 'mock_dev_token',
  );
});

/// UI state for Screen S44 (McpPage).
class McpState {
  final bool isCraftAiConnected;
  final bool isLoading;
  final String? errorMessage;
  final List<McpTool> activeTools;
  final List<McpLessonSummary> searchResults;
  final String searchQuery;
  final McpLessonDetail? selectedLesson;
  final bool isSearching;
  final String? savedNoteMessage;

  const McpState({
    this.isCraftAiConnected = false,
    this.isLoading = false,
    this.errorMessage,
    this.activeTools = const [],
    this.searchResults = const [],
    this.searchQuery = '',
    this.selectedLesson,
    this.isSearching = false,
    this.savedNoteMessage,
  });

  McpState copyWith({
    bool? isCraftAiConnected,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    List<McpTool>? activeTools,
    List<McpLessonSummary>? searchResults,
    String? searchQuery,
    McpLessonDetail? selectedLesson,
    bool clearSelectedLesson = false,
    bool? isSearching,
    String? savedNoteMessage,
    bool clearSavedNote = false,
  }) {
    return McpState(
      isCraftAiConnected: isCraftAiConnected ?? this.isCraftAiConnected,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      activeTools: activeTools ?? this.activeTools,
      searchResults: searchResults ?? this.searchResults,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedLesson: clearSelectedLesson
          ? null
          : (selectedLesson ?? this.selectedLesson),
      isSearching: isSearching ?? this.isSearching,
      savedNoteMessage: clearSavedNote
          ? null
          : (savedNoteMessage ?? this.savedNoteMessage),
    );
  }
}

/// Controller managing MCP connector state, search, and note persistence (F15-01 - F15-09).
class McpNotifier extends Notifier<McpState> {
  final String ownerId;

  McpNotifier(this.ownerId);

  @override
  McpState build() {
    return const McpState();
  }

  McpClient get _client => ref.read(mcpClientProvider);
  ToolsDispatcher get _dispatcher => ref.read(toolsDispatcherProvider);

  /// Connects to CraftAI Lessons MCP server (F15-01, F15-03, F15-04).
  Future<void> connectCraftAi() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final tools = await _client.connect();
      final initialResults = await _client.searchLessons(query: '');

      state = state.copyWith(
        isCraftAiConnected: true,
        isLoading: false,
        activeTools: tools,
        searchResults: initialResults,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Ошибка подключения к MCP-шлюзу: $e',
      );
    }
  }

  /// Disconnects connector, invalidating active tools and cached results (F15-08, F15-09).
  Future<void> disconnectCraftAi() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _client.disconnect();
      state = state.copyWith(
        isCraftAiConnected: false,
        isLoading: false,
        activeTools: const [],
        searchResults: const [],
        clearSelectedLesson: true,
        clearSavedNote: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Ошибка отключения MCP-шлюза: $e',
      );
    }
  }

  /// Searches lessons in the catalog via search_lessons tool (F15-06).
  Future<void> search(String query) async {
    if (!state.isCraftAiConnected) return;

    state = state.copyWith(
      isSearching: true,
      searchQuery: query,
      clearError: true,
    );
    try {
      final results = await _client.searchLessons(query: query);
      state = state.copyWith(isSearching: false, searchResults: results);
    } catch (e) {
      state = state.copyWith(
        isSearching: false,
        errorMessage: 'Ошибка поиска в каталоге уроков: $e',
      );
    }
  }

  /// Loads full lesson detail for preview (F15-06).
  Future<void> selectLesson(String lessonId) async {
    if (!state.isCraftAiConnected) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearSavedNote: true,
    );
    try {
      final detail = await _client.getLesson(lessonId);
      state = state.copyWith(isLoading: false, selectedLesson: detail);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Ошибка загрузки конспекта урока: $e',
      );
    }
  }

  /// Saves the found lesson to assistant private notes via confirmation state machine (F15-06).
  Future<ToolExecutionResult> saveLessonToNotes(McpLessonDetail lesson) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // 1. Dispatch through ToolsDispatcher (which requires confirmation for mutating createNote)
      final result = await _dispatcher.dispatch(
        ownerId: ownerId,
        toolName: ToolsRegistry.createNote,
        args: {
          'title': 'План урока: ${lesson.title}',
          'content': '${lesson.summary}\n\n${lesson.content}',
        },
        invocationSource: 'mcp_catalog_connector',
      );

      // If needs confirmation, auto-approve for the explicit user tap action in S44 UI
      if (result.requiresConfirmation && result.pendingAction != null) {
        final confirmed = await _dispatcher.confirmAndExecutePendingAction(
          ownerId: ownerId,
          invocationId: result.pendingAction!.invocationId,
        );

        state = state.copyWith(
          isLoading: false,
          savedNoteMessage:
              'Урок «${lesson.title}» успешно сохранён в ваши личные заметки.',
        );
        return confirmed;
      }

      state = state.copyWith(
        isLoading: false,
        savedNoteMessage:
            'Урок «${lesson.title}» успешно сохранён в ваши личные заметки.',
      );
      return result;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Ошибка сохранения урока в заметки: $e',
      );
      return ToolExecutionResult.failure(
        toolName: ToolsRegistry.createNote,
        errorMessage: '$e',
      );
    }
  }

  void clearSelection() {
    state = state.copyWith(clearSelectedLesson: true, clearSavedNote: true);
  }
}

/// Provider family for McpNotifier by ownerId.
final mcpControllerProvider =
    NotifierProvider.family<McpNotifier, McpState, String>(
      (arg) => McpNotifier(arg),
    );
