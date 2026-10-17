import '../../../core/errors/app_failure.dart';

class LegalDocument {
  const LegalDocument({required this.body, required this.revision});
  final String body;
  final String revision;
}

/// Approved, localized content supplied by the real CraftAI integration.
class AuthLegalDocuments {
  const AuthLegalDocuments({required this.terms, required this.privacy});
  final LegalDocument terms;
  final LegalDocument privacy;

  bool get isUsable =>
      terms.body.trim().isNotEmpty &&
      privacy.body.trim().isNotEmpty &&
      terms.revision.trim().isNotEmpty &&
      privacy.revision.trim().isNotEmpty;
}

/// Client port, not a claim about existing HTTP paths or JSON schemas.
/// The real adapter must publish authenticated state through SessionRepository
/// only after secure persistence succeeds. UI never fabricates a session.
abstract interface class AuthGateway {
  bool get isAvailable;
  AuthLegalDocuments? documentsFor(String languageCode);
  Future<void> signIn({required String email, required String password});
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String termsRevision,
    required String privacyRevision,
  });
  Future<void> requestPasswordReset({required String email});
  Future<void> resetPassword({required String token, required String newPassword});
}

final class NotConnectedAuthGateway implements AuthGateway {
  const NotConnectedAuthGateway();
  @override
  bool get isAvailable => false;
  @override
  AuthLegalDocuments? documentsFor(String languageCode) => null;
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async => throw const AppFailure(AppFailureCode.serviceUnavailable);
  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String termsRevision,
    required String privacyRevision,
  }) async => throw const AppFailure(AppFailureCode.serviceUnavailable);
  @override
  Future<void> requestPasswordReset({required String email}) async =>
      throw const AppFailure(AppFailureCode.serviceUnavailable);
  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async => throw const AppFailure(AppFailureCode.serviceUnavailable);
}
