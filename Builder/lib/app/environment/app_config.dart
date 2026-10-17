import 'package:flutter/foundation.dart';

enum AppEnvironment { development, staging, production }

/// Public operational settings only. Never accepts provider credentials.
class AppConfig {
  const AppConfig({required this.environment, this.apiBaseUri});

  factory AppConfig.fromValues({
    required String environment,
    required String apiBaseUrl,
  }) {
    final selected = switch (environment) {
      'dev' => AppEnvironment.development,
      'staging' => AppEnvironment.staging,
      'prod' => AppEnvironment.production,
      _ => throw const FormatException('Unknown application environment.'),
    };
    if (apiBaseUrl.isEmpty) return AppConfig(environment: selected);
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Invalid API base URL.');
    }
    final loopback = const ['localhost', '127.0.0.1', '::1'].contains(uri.host);
    final devHttp =
        selected == AppEnvironment.development &&
        uri.scheme == 'http' &&
        loopback;
    if (uri.scheme != 'https' && !devHttp) {
      throw const FormatException('HTTPS is required for the API.');
    }
    return AppConfig(environment: selected, apiBaseUri: uri);
  }

  factory AppConfig.fromEnvironment() {
    const envPassed = String.fromEnvironment('APP_ENV');
    const apiPassed = String.fromEnvironment('CRAFTAI_API_BASE_URL');

    final selectedEnv = envPassed.isNotEmpty
        ? envPassed
        : (kDebugMode ? 'dev' : 'prod');
    final selectedApi = apiPassed.isNotEmpty
        ? apiPassed
        : (kDebugMode ? 'https://localhost:5001' : '');

    return AppConfig.fromValues(
      environment: selectedEnv,
      apiBaseUrl: selectedApi,
    );
  }

  final AppEnvironment environment;
  final Uri? apiBaseUri;
}
