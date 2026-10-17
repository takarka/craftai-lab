import 'assistant_setup.dart';

class InitialWorkspace {
  const InitialWorkspace({required this.ownerId, required this.setup});
  final String ownerId;
  final AssistantSetup setup;
}

/// A transient write permission. Never serialize this callback or put it in an API.
class WorkspaceWritePermit {
  WorkspaceWritePermit({required this.ownerId, required this.canCommit}) {
    if (ownerId.trim().isEmpty) throw ArgumentError('Owner ID is required.');
  }
  final String ownerId;
  final bool Function() canCommit;
  bool get isCurrent => canCommit();
}

/// The F03 implementation must commit atomically and be idempotent per owner
/// in this installation. Existing workspaces must not be overwritten.
/// Recheck permit.isCurrent inside the write transaction before committing.
abstract interface class InitialWorkspaceRepository {
  bool get isAvailable;
  Future<InitialWorkspace> createIfAbsent({
    required WorkspaceWritePermit permit,
    required AssistantSetup setup,
  });
}

class WorkspaceUnavailable implements Exception {
  const WorkspaceUnavailable();
}

/// F01 native/storage verification is still required before storing real data.
final class NotConnectedWorkspaceRepository
    implements InitialWorkspaceRepository {
  const NotConnectedWorkspaceRepository();
  @override
  bool get isAvailable => false;
  @override
  Future<InitialWorkspace> createIfAbsent({
    required WorkspaceWritePermit permit,
    required AssistantSetup setup,
  }) async => throw const WorkspaceUnavailable();
}
