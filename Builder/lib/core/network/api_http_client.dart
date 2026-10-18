import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../app/environment/app_config.dart';

/// The local development API uses a self-signed certificate over adb reverse.
http.Client createApiHttpClient(AppConfig? config) {
  final uri = config?.apiBaseUri;
  if (!kIsWeb &&
      kDebugMode &&
      config?.environment == AppEnvironment.development &&
      uri != null &&
      const ['localhost', '127.0.0.1', '::1'].contains(uri.host)) {
    final client = HttpClient()
      ..badCertificateCallback = (_, host, port) =>
          host == uri.host && port == uri.port;
    return IOClient(client);
  }
  return http.Client();
}
