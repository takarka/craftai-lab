// Imported only by the DEV preview entrypoint, never by production bootstrap.
import '../features/session/session_repository.dart';
import '../features/onboarding/domain/assistant_setup.dart';
import '../features/onboarding/domain/initial_workspace_repository.dart';

final class OnboardingPreviewSession implements SessionRepository {
  const OnboardingPreviewSession();
  @override
  Stream<SessionSnapshot> watchSession() => Stream.value(
    AuthenticatedSession(
      ownerId: 'dev-onboarding-preview',
      onboardingComplete: false,
    ),
  );
}

final class InMemoryOnboardingPreview implements InitialWorkspaceRepository {
  final _workspaces = <String, InitialWorkspace>{};
  @override
  bool get isAvailable => true;
  @override
  Future<InitialWorkspace> createIfAbsent({
    required WorkspaceWritePermit permit,
    required AssistantSetup setup,
  }) async {
    if (permit.ownerId != 'dev-onboarding-preview' || !setup.ready) {
      throw ArgumentError('Invalid preview workspace.');
    }
    if (!permit.isCurrent) throw const WorkspaceUnavailable();
    return _workspaces.putIfAbsent(
      permit.ownerId,
      () => InitialWorkspace(ownerId: permit.ownerId, setup: setup),
    );
  }
}
