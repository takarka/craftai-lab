import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/storage/database/storage_database.dart';
import '../core/storage/storage_providers.dart';
import 'app.dart';
import 'environment/app_config.dart';
import 'providers.dart';

void bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig? config;
  try {
    config = AppConfig.fromEnvironment();
  } on FormatException {
    // Do not expose the invalid value: it may contain credentials.
    config = null;
  }

  StorageDatabase? database;
  if (!kIsWeb) {
    try {
      final dir = await getApplicationSupportDirectory();
      final path = p.join(dir.path, 'craftai_builder.db');
      database = StorageDatabase(databasePath: path);
    } catch (_) {
      database = null;
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        if (database != null)
          storageDatabaseProvider.overrideWithValue(database),
      ],
      child: const BuilderApp(),
    ),
  );
}
