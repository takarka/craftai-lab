sealed class SessionSnapshot {
  const SessionSnapshot();
}

final class SignedOut extends SessionSnapshot {
  const SignedOut();
}

final class AuthenticatedSession extends SessionSnapshot {
  AuthenticatedSession({
    required this.ownerId,
    required this.onboardingComplete,
  }) {
    if (ownerId.trim().isEmpty) throw ArgumentError('Owner ID is required.');
  }

  final String ownerId;
  final bool onboardingComplete;
}

/// F04 will supply secure restoration and the real CraftAI auth adapter.
abstract interface class SessionRepository {
  Stream<SessionSnapshot> watchSession();
}

/// No network, credentials, fabricated account or demo login in the app.
final class NotConnectedSessionRepository implements SessionRepository {
  const NotConnectedSessionRepository();

  @override
  Stream<SessionSnapshot> watchSession() =>
      Stream<SessionSnapshot>.value(const SignedOut());
}
