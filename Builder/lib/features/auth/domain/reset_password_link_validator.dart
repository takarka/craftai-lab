sealed class ResetLinkValidationResult {
  const ResetLinkValidationResult();
}

final class ValidResetToken extends ResetLinkValidationResult {
  const ValidResetToken(this.token);
  final String token;
}

final class InvalidResetLink extends ResetLinkValidationResult {
  const InvalidResetLink(this.reason);
  final String reason;
}

/// Client validator for password reset app and universal links (F04-04).
/// Never logs raw links or sensitive tokens.
final class ResetPasswordLinkValidator {
  const ResetPasswordLinkValidator({
    this.allowedHosts = const {'craftai.kz', 'api.craftai.kz', 'localhost'},
    this.allowedSchemes = const {'https', 'craftai'},
  });

  final Set<String> allowedHosts;
  final Set<String> allowedSchemes;

  ResetLinkValidationResult validate(Uri uri) {
    if (!allowedSchemes.contains(uri.scheme.toLowerCase())) {
      return const InvalidResetLink('Недопустимая схема ссылки.');
    }

    if (uri.host.isNotEmpty && !allowedHosts.contains(uri.host.toLowerCase())) {
      return const InvalidResetLink('Недопустимый узел (host) ссылки.');
    }

    final token = uri.queryParameters['token'] ?? uri.queryParameters['t'];
    if (token == null || token.trim().isEmpty) {
      return const InvalidResetLink('Отсутствует токен восстановления пароля.');
    }

    final trimmed = token.trim();
    // Tokens must be safe base64url or hex alphanumeric tokens (min 16 chars)
    final tokenRegex = RegExp(r'^[A-Za-z0-9_\-\.]{16,256}$');
    if (!tokenRegex.hasMatch(trimmed)) {
      return const InvalidResetLink('Некорректный формат токена.');
    }

    return ValidResetToken(trimmed);
  }
}
