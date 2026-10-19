import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_providers.dart';
import '../domain/pending_action.dart';
import '../domain/tool_definition.dart';
import '../domain/tool_grant.dart';
import '../domain/tools_dispatcher.dart';
import '../domain/tools_registry.dart';
import '../domain/tools_repository.dart';
import '../infrastructure/persistent_tools_repository.dart';

/// Global provider for ToolsRepository.
final toolsRepositoryProvider = Provider<ToolsRepository>((ref) {
  final db = ref.watch(storageDatabaseProvider);
  if (db == null) return InMemoryToolsRepository();
  return PersistentToolsRepository(database: db);
});

/// Global provider for ToolsDispatcher.
final toolsDispatcherProvider = Provider<ToolsDispatcher>((ref) {
  final repo = ref.watch(toolsRepositoryProvider);
  return ToolsDispatcher(repository: repo);
});

/// View-model item for Screen S43.
class ToolItemState {
  final ToolDefinition definition;
  final ToolGrant grant;
  final OsPermissionStatus osPermission;

  const ToolItemState({
    required this.definition,
    required this.grant,
    required this.osPermission,
  });

  bool get isEnabled => grant.isEnabled;
  bool get hasOsPermission =>
      osPermission == OsPermissionStatus.granted ||
      osPermission == OsPermissionStatus.notRequired;
}

/// UI State for Screen S43.
class ToolsState {
  final List<ToolItemState> toolItems;
  final List<PendingAction> pendingActions;
  final bool isLoading;
  final String? errorMessage;

  const ToolsState({
    this.toolItems = const [],
    this.pendingActions = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  ToolsState copyWith({
    List<ToolItemState>? toolItems,
    List<PendingAction>? pendingActions,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ToolsState(
      toolItems: toolItems ?? this.toolItems,
      pendingActions: pendingActions ?? this.pendingActions,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// Notifier managing tools state, grants, and pending confirmation actions for Screen S43.
class ToolsNotifier extends Notifier<ToolsState> {
  final String ownerId;

  ToolsNotifier(this.ownerId);

  @override
  ToolsState build() {
    Future.microtask(() => load());
    return const ToolsState(isLoading: true);
  }

  ToolsRepository get _repo => ref.read(toolsRepositoryProvider);
  ToolsDispatcher get _dispatcher => ref.read(toolsDispatcherProvider);

  Future<void> load() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _repo.ensureDefaultGrants(ownerId);
      final grants = await _repo.getGrants(ownerId);
      final grantsMap = {for (final g in grants) g.toolName: g};

      final items = <ToolItemState>[];
      for (final def in ToolsRegistry.allTools) {
        final grant =
            grantsMap[def.name] ??
            ToolGrant(
              ownerId: ownerId,
              toolName: def.name,
              isEnabled: def.name != ToolsRegistry.webSearch,
              updatedAtUtc: DateTime.now().toUtc(),
            );
        final osPerm = await _repo.getOsPermission(def.name);
        items.add(
          ToolItemState(definition: def, grant: grant, osPermission: osPerm),
        );
      }

      final pending = await _repo.getPendingActions(
        ownerId,
        status: PendingActionStatus.pending,
      );

      state = state.copyWith(
        toolItems: items,
        pendingActions: pending
            .where(
              (action) => ToolsRegistry.getByName(action.actionName) != null,
            )
            .toList(),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Ошибка загрузки инструментов: $e',
      );
    }
  }

  Future<void> toggleGrant(String toolName, bool isEnabled) async {
    try {
      await _repo.setGrant(
        ownerId: ownerId,
        toolName: toolName,
        isEnabled: isEnabled,
      );
      state = state.copyWith(
        toolItems: state.toolItems.map((item) {
          if (item.definition.name == toolName) {
            return ToolItemState(
              definition: item.definition,
              grant: item.grant.copyWith(isEnabled: isEnabled),
              osPermission: item.osPermission,
            );
          }
          return item;
        }).toList(),
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Ошибка сохранения разрешения: $e');
    }
  }

  Future<void> setOsPermission(
    String toolName,
    OsPermissionStatus status,
  ) async {
    try {
      await _repo.setOsPermission(toolName, status);
      state = state.copyWith(
        toolItems: state.toolItems.map((item) {
          if (item.definition.name == toolName) {
            return ToolItemState(
              definition: item.definition,
              grant: item.grant,
              osPermission: status,
            );
          }
          return item;
        }).toList(),
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Ошибка обновления статуса ОС: $e');
    }
  }

  Future<ToolExecutionResult> confirmAction(String invocationId) async {
    final result = await _dispatcher.confirmAndExecutePendingAction(
      ownerId: ownerId,
      invocationId: invocationId,
    );
    await load();
    return result;
  }

  Future<void> rejectAction(String invocationId) async {
    await _dispatcher.rejectPendingAction(
      ownerId: ownerId,
      invocationId: invocationId,
    );
    await load();
  }

  Future<void> createEducationalTestAction() async {
    final now = DateTime.now().toUtc();
    final action = PendingAction(
      invocationId: 'act_test_${now.millisecondsSinceEpoch}',
      ownerId: ownerId,
      workspaceEpoch: 1,
      actionName: ToolsRegistry.createCalendarEvent,
      paramsHash: PendingAction.computeParamsHash({
        'title': 'Родительское собрание 7Б',
        'start_time': '2026-10-20T18:00:00Z',
        'end_time': '2026-10-20T19:30:00Z',
        'location': 'Кабинет 304',
      }),
      params: {
        'title': 'Родительское собрание 7Б',
        'start_time': '2026-10-20T18:00:00Z',
        'end_time': '2026-10-20T19:30:00Z',
        'location': 'Кабинет 304',
      },
      status: PendingActionStatus.pending,
      expiresAtUtc: now.add(const Duration(minutes: 15)),
      createdAtUtc: now,
    );
    await _repo.createPendingAction(action);
    await load();
  }
}

/// Family provider for ToolsNotifier by ownerId.
final toolsControllerProvider =
    NotifierProvider.family<ToolsNotifier, ToolsState, String>(
      (arg) => ToolsNotifier(arg),
    );
