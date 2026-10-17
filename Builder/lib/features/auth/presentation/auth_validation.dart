import '../../../app/localization/app_localizations.dart';

abstract final class AuthValidation {
  static String? requiredText(String? value, AppLocalizations strings) =>
      value == null || value.trim().isEmpty ? strings.fieldRequired : null;

  static String? email(String? value, AppLocalizations strings) {
    if (requiredText(value, strings) != null) return strings.fieldRequired;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value!.trim())
        ? null
        : strings.invalidEmail;
  }

  // Password policy is owned by CraftAI; do not invent client-only rules.
  // Password whitespace is meaningful and must never be trimmed.
  static String? password(String? value, AppLocalizations strings) =>
      value == null || value.isEmpty ? strings.fieldRequired : null;

  static String? confirmation(
    String? value,
    String password,
    AppLocalizations strings,
  ) => value == null || value.isEmpty
      ? strings.fieldRequired
      : value != password
      ? strings.passwordMismatch
      : null;
}
