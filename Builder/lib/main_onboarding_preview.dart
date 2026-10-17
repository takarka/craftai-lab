import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/environment/app_config.dart';
import 'app/providers.dart';
import 'features/onboarding/application/onboarding_controller.dart';
import 'preview/onboarding_preview.dart';

void main() {
  if (kReleaseMode) throw StateError('Onboarding preview is development-only.');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(environment: AppEnvironment.development),
        ),
        developmentPreviewProvider.overrideWithValue(true),
        sessionRepositoryProvider.overrideWithValue(
          const OnboardingPreviewSession(),
        ),
        initialWorkspaceRepositoryProvider.overrideWithValue(
          InMemoryOnboardingPreview(),
        ),
      ],
      child: const BuilderApp(),
    ),
  );
}
