import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../session/session_providers.dart';
import '../domain/auth_gateway.dart';
import '../infrastructure/craft_ai_auth_gateway.dart';

enum AuthFormKind { signIn, register, recovery, resetPassword }

final authGatewayProvider = Provider<AuthGateway>((ref) {
  final config = ref.watch(appConfigProvider);
  final sessionRepo = ref.watch(sessionRepositoryProvider);
  final tokenStorage = ref.watch(secureTokenStorageProvider);

  if (config?.apiBaseUri != null) {
    return CraftAiAuthGateway(
      baseUri: config!.apiBaseUri!,
      sessionRepository: sessionRepo,
      tokenStorage: tokenStorage,
    );
  }

  return const NotConnectedAuthGateway();
});

class AuthSubmissionState {
  const AuthSubmissionState({
    this.busy = false,
    this.failure,
    this.recoverySent = false,
    this.resetComplete = false,
  });
  final bool busy;
  final AppFailure? failure;
  final bool recoverySent;
  final bool resetComplete;
}

final authControllerProvider = NotifierProvider.autoDispose
    .family<AuthController, AuthSubmissionState, AuthFormKind>(
      AuthController.new,
    );

class AuthController extends Notifier<AuthSubmissionState> {
  AuthController(this.kind);
  final AuthFormKind kind;
  bool _active = true;

  @override
  AuthSubmissionState build() {
    _active = true;
    ref.onDispose(() => _active = false);
    return const AuthSubmissionState();
  }

  Future<void> submit(Future<void> Function(AuthGateway) action) async {
    if (state.busy || state.recoverySent || state.resetComplete) return;
    final gateway = ref.read(authGatewayProvider);
    if (!gateway.isAvailable) {
      state = const AuthSubmissionState(
        failure: AppFailure(AppFailureCode.serviceUnavailable),
      );
      return;
    }
    state = const AuthSubmissionState(busy: true);
    try {
      await action(gateway);
      if (_active) {
        state = AuthSubmissionState(
          recoverySent: kind == AuthFormKind.recovery,
          resetComplete: kind == AuthFormKind.resetPassword,
        );
      }
    } on AppFailure catch (failure) {
      if (_active) state = AuthSubmissionState(failure: failure);
    } catch (_) {
      if (_active) {
        state = const AuthSubmissionState(
          failure: AppFailure(AppFailureCode.unexpected),
        );
      }
    }
  }
}
