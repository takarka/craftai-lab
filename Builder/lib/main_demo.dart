import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'demo/demo_app.dart';

Future<void> main() async {
  if (kReleaseMode) throw StateError('Demo mode is development-only.');
  WidgetsFlutterBinding.ensureInitialized();
  final environment = await DemoEnvironment.create();
  runApp(DemoApp(environment: environment));
}
