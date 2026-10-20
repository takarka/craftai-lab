import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/providers.dart';
import '../../../app/router/app_router.dart';
import '../../../core/network/api_http_client.dart';
import '../../models/infrastructure/craft_ai_client.dart';
import '../../session/session_providers.dart';
import '../../session/session_repository.dart';
import 'push_gateway.dart';
import 'push_registration_service.dart';

class _BoundApi implements BoundPushDeviceApi {
  const _BoundApi(this.api, this.accessToken);
  final CraftAiClient api;
  final String accessToken;
  @override
  Future<void> register(String id, Map<String, dynamic> input) async {
    await api.requestJson(
      'PUT',
      '/builder/devices/${Uri.encodeComponent(id)}',
      body: input,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
  }

  @override
  Future<void> revoke(String id) async {
    await api.requestJson(
      'DELETE',
      '/builder/devices/${Uri.encodeComponent(id)}',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
  }
}

final pushRegistrationServiceProvider = Provider<PushRegistrationService>((
  ref,
) {
  final config = ref.watch(appConfigProvider);
  final storage = ref.watch(secureTokenStorageProvider);
  final gateway = FirebasePushGateway();
  final http = createApiHttpClient(config);
  final service = PushRegistrationService(
    gateway: gateway,
    preferences: const SecurePushPreferences(),
    appVersion: () async {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    },
    bindApi: (owner) async {
      if (config?.apiBaseUri == null || await storage.readOwnerId() != owner) {
        return null;
      }
      final tokens = await storage.readTokens();
      if (tokens == null || await storage.readOwnerId() != owner) return null;
      return _BoundApi(
        CraftAiClient(baseUri: config!.apiBaseUri!, httpClient: http),
        tokens.accessToken,
      );
    },
  );
  ref.onDispose(() {
    unawaited(
      service.dispose().whenComplete(() async {
        await gateway.dispose();
        http.close();
      }),
    );
  });
  return service;
});

final pushStatusProvider = StreamProvider<PushStatus>((ref) async* {
  final service = ref.watch(pushRegistrationServiceProvider);
  yield service.status;
  yield* service.states;
});

final pushMessengerKeyProvider = Provider(
  (ref) => GlobalKey<ScaffoldMessengerState>(),
);

/// App-owned subscriptions, never a permission prompt during startup/sign-in.
final pushLifecycleProvider = Provider<void>((ref) {
  final service = ref.watch(pushRegistrationServiceProvider);
  void sync({bool sessionChanged = false}) {
    final session = ref.read(sessionProvider).asData?.value;
    if (session == null) return; // Wait for secure session restoration.
    unawaited(
      service
          .setOwner(
            session is AuthenticatedSession ? session.ownerId : null,
            sessionChanged: sessionChanged,
            locale: ref.read(appLocaleProvider)?.languageCode == 'kk'
                ? 'kk'
                : 'ru',
          )
          .catchError((_) {}),
    );
  }

  ref.listen(sessionProvider, (_, next) {
    ref.read(pushMessengerKeyProvider).currentState?.clearSnackBars();
    scheduleMicrotask(() {
      if (ref.mounted) sync(sessionChanged: true);
    });
  }, fireImmediately: true);
  ref.listen(appLocaleProvider, (_, next) {
    scheduleMicrotask(() {
      if (ref.mounted) sync();
    });
  });
  final lifecycle = AppLifecycleListener(onResume: () => sync());
  final events = service.events.listen((event) {
    bool active() {
      if (!ref.mounted) return false;
      final session = ref.read(sessionProvider).asData?.value;
      return session is AuthenticatedSession &&
          session.ownerId == event.ownerId;
    }

    void open() {
      if (active()) {
        ref.read(appRouterProvider).push('/automation/runs/${event.runId}');
      }
    }

    if (!active()) return;
    if (event.opened) {
      open();
      return;
    }
    final kk = ref.read(appLocaleProvider)?.languageCode == 'kk';
    ref
        .read(pushMessengerKeyProvider)
        .currentState
        ?.showSnackBar(
          SnackBar(
            content: Text(kk ? 'AI нәтижесі дайын' : 'Результат ИИ готов'),
            action: SnackBarAction(
              label: kk ? 'Ашу' : 'Открыть',
              onPressed: open,
            ),
          ),
        );
  });
  ref.onDispose(() {
    lifecycle.dispose();
    unawaited(events.cancel());
  });
});
