import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/platform_capabilities.dart';
import '../features/session/session_repository.dart';
import 'environment/app_config.dart';

final appConfigProvider = Provider<AppConfig?>((ref) => null);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => const NotConnectedSessionRepository(),
);

final sessionProvider = StreamProvider<SessionSnapshot>(
  (ref) => ref.watch(sessionRepositoryProvider).watchSession(),
);

final platformCapabilitiesProvider = Provider<PlatformCapabilities>(
  (ref) => PlatformCapabilities.current(),
);

class AppLocale extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  void select(Locale locale) {
    if (!const ['ru', 'kk'].contains(locale.languageCode)) {
      throw ArgumentError('Unsupported application locale.');
    }
    state = Locale(locale.languageCode);
  }
}

final appLocaleProvider = NotifierProvider<AppLocale, Locale?>(AppLocale.new);

final developmentPreviewProvider = Provider<bool>((ref) => false);
