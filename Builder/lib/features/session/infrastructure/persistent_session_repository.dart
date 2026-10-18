import 'dart:async';
import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../../../core/storage/workspace/workspace_storage_service.dart';
import '../domain/auth_tokens.dart';
import '../session_repository.dart';
import 'secure_token_storage.dart';

final class PersistentSessionRepository implements SessionRepository {
  PersistentSessionRepository({
    required this.tokenStorage,
    required this.database,
    required this.workspaceStorageService,
    this.tokenRefresher,
  }) {
    _controller = StreamController<SessionSnapshot>.broadcast();
  }

  final SecureTokenStorage tokenStorage;
  final StorageDatabase database;
  final WorkspaceStorageService workspaceStorageService;
  final Future<AuthTokens> Function(String refreshToken)? tokenRefresher;

  late final StreamController<SessionSnapshot> _controller;
  SessionSnapshot _currentSnapshot = const SignedOut();
  Completer<AuthTokens>? _refreshCompleter;

  SessionSnapshot get currentSnapshot => _currentSnapshot;

  @override
  Stream<SessionSnapshot> watchSession() =>
      Stream<SessionSnapshot>.multi((sink) {
        final subscription = _controller.stream.listen(
          sink.add,
          onError: sink.addError,
          onDone: sink.close,
        );
        sink.onCancel = subscription.cancel;
        // Restore before emitting a signed-out state so startup can resume the
        // saved account without briefly showing the login form.
        unawaited(restoreSession().then<void>((_) {}, onError: sink.addError));
      });

  /// Restores session from secure storage upon application startup.
  Future<SessionSnapshot> restoreSession() async {
    final ownerId = await tokenStorage.readOwnerId();
    final tokens = await tokenStorage.readTokens();

    if (ownerId == null || tokens == null || ownerId.trim().isEmpty) {
      _emit(const SignedOut());
      return const SignedOut();
    }

    // Check token expiry and refresh if expired and refresher is configured
    var activeTokens = tokens;
    if (activeTokens.isExpired && tokenRefresher != null) {
      try {
        activeTokens = await refreshTokens();
      } catch (e) {
        // If offline / network error, do not discard local assistant data (F04-07).
        // If permanent revocation or invalid grant, sign out.
        if (_isPermanentAuthError(e)) {
          await signOut();
          return const SignedOut();
        }
      }
    }

    if (!database.isOpen) {
      await database.open();
    }

    // Determine onboarding completion from local database
    final onboardingComplete = await isLocalOnboardingComplete(ownerId);

    // Open workspace partition for active owner
    await workspaceStorageService.openWorkspace(ownerId: ownerId);

    final session = AuthenticatedSession(
      ownerId: ownerId,
      onboardingComplete: onboardingComplete,
    );
    _emit(session);
    return session;
  }

  /// Saves newly authenticated session and switches active workspace partition.
  Future<void> saveSession({
    required String ownerId,
    required AuthTokens tokens,
    bool mustChangePassword = false,
  }) async {
    if (ownerId.trim().isEmpty) {
      throw ArgumentError('Owner ID is required.');
    }

    await tokenStorage.writeSession(ownerId: ownerId, tokens: tokens);

    if (!database.isOpen) {
      await database.open();
    }

    final onboardingComplete = await isLocalOnboardingComplete(ownerId);
    await workspaceStorageService.openWorkspace(ownerId: ownerId);

    final session = AuthenticatedSession(
      ownerId: ownerId,
      onboardingComplete: onboardingComplete,
      mustChangePassword: mustChangePassword,
    );
    _emit(session);
  }

  /// Single-flight token refresh mutex.
  Future<AuthTokens> refreshTokens() async {
    if (_refreshCompleter != null) {
      return await _refreshCompleter!.future;
    }

    final completer = Completer<AuthTokens>();
    _refreshCompleter = completer;

    try {
      final tokens = await tokenStorage.readTokens();
      final ownerId = await tokenStorage.readOwnerId();
      if (tokens == null || ownerId == null) {
        throw StateError('No active session available to refresh.');
      }

      if (tokenRefresher == null) {
        throw StateError('No tokenRefresher configured.');
      }

      final newTokens = await tokenRefresher!(tokens.refreshToken);
      await tokenStorage.writeSession(ownerId: ownerId, tokens: newTokens);
      completer.complete(newTokens);
      return newTokens;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }

  /// Signs out, wipes memory caches, closes active workspace and clears token storage.
  Future<void> signOut() async {
    await workspaceStorageService.closeActiveWorkspace();
    await tokenStorage.clearSession();
    _emit(const SignedOut());
  }

  /// Checks if an assistant has already been created in the local database for [ownerId].
  Future<bool> isLocalOnboardingComplete(String ownerId) async {
    if (!database.isOpen) {
      await database.open();
    }
    final configs = await database.db.query(
      StorageSchemaV1.tableAssistantConfigurations,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    return configs.isNotEmpty;
  }

  /// Updates active session snapshot to reflect that onboarding has completed.
  void markOnboardingComplete(String ownerId) {
    if (_currentSnapshot is AuthenticatedSession &&
        (_currentSnapshot as AuthenticatedSession).ownerId == ownerId) {
      _emit(AuthenticatedSession(ownerId: ownerId, onboardingComplete: true));
    }
  }

  /// Updates active session snapshot to reflect that onboarding needs to be redone (e.g. after D05 reset).
  void markOnboardingIncomplete(String ownerId) {
    if (_currentSnapshot is AuthenticatedSession &&
        (_currentSnapshot as AuthenticatedSession).ownerId == ownerId) {
      _emit(AuthenticatedSession(ownerId: ownerId, onboardingComplete: false));
    }
  }

  void markPasswordChanged() {
    final current = _currentSnapshot;
    if (current is AuthenticatedSession && current.mustChangePassword) {
      _emit(
        AuthenticatedSession(
          ownerId: current.ownerId,
          onboardingComplete: current.onboardingComplete,
        ),
      );
    }
  }

  void _emit(SessionSnapshot snapshot) {
    _currentSnapshot = snapshot;
    if (!_controller.isClosed) {
      _controller.add(snapshot);
    }
  }

  bool _isPermanentAuthError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('invalid_grant') ||
        msg.contains('token_revoked') ||
        msg.contains('unauthorized') ||
        msg.contains('401');
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
