import 'pending_action.dart';
import 'tool_definition.dart';
import 'tool_grant.dart';
import 'tool_invocation.dart';

/// Repository interface for tools authorization, pending actions, and invocation logs (F14-01..F14-12).
abstract class ToolsRepository {
  /// Returns all grants for the given workspace owner.
  Future<List<ToolGrant>> getGrants(String ownerId);

  /// Returns a specific tool grant.
  Future<ToolGrant?> getGrant(String ownerId, String toolName);

  /// Enables or disables a tool authorization grant.
  Future<void> setGrant({
    required String ownerId,
    required String toolName,
    required bool isEnabled,
    String permissionScope = 'standard',
  });

  /// Seeds default grants for all registered tools if none exist.
  Future<void> ensureDefaultGrants(String ownerId);

  /// Saves a new pending action requiring teacher confirmation (F14-05).
  Future<PendingAction> createPendingAction(PendingAction action);

  /// Fetches a pending action by its invocation ID.
  Future<PendingAction?> getPendingAction(String invocationId);

  /// Fetches all pending actions for an owner, optionally filtered by status.
  Future<List<PendingAction>> getPendingActions(
    String ownerId, {
    PendingActionStatus? status,
  });

  /// Updates the status of a pending action.
  Future<void> updatePendingActionStatus({
    required String invocationId,
    required PendingActionStatus status,
  });

  /// Logs a tool execution invocation in SQLite (tableToolInvocations) (F14-11).
  Future<void> logInvocation(ToolInvocationRecord record);

  /// Fetches logged tool invocations for an owner.
  Future<List<ToolInvocationRecord>> getInvocations(
    String ownerId, {
    int limit = 20,
  });

  /// Returns current OS permission status for a tool.
  Future<OsPermissionStatus> getOsPermission(String toolName);

  /// Updates OS permission status in local state/storage.
  Future<void> setOsPermission(String toolName, OsPermissionStatus status);
}
