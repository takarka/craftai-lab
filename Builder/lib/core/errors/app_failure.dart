enum AppFailureCode {
  invalidCredentials,
  accountExists,
  weakPassword,
  networkUnavailable,
  rateLimited,
  serviceUnavailable,
  unexpected,
}

/// Contains no response body, URL, password, token or provider diagnostics.
final class AppFailure implements Exception {
  const AppFailure(this.code);
  final AppFailureCode code;
}
