import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'environment/app_config.dart';
import 'providers.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig? config;
  try {
    config = AppConfig.fromEnvironment();
  } on FormatException {
    // Do not expose the invalid value: it may contain credentials.
    config = null;
  }
  runApp(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config)],
      child: const BuilderApp(),
    ),
  );
}
