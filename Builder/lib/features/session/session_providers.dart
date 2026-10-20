import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/network/api_http_client.dart';
import '../../core/storage/storage_providers.dart';
import 'infrastructure/persistent_session_repository.dart';
import 'infrastructure/secure_token_storage.dart';
import 'infrastructure/refreshing_token_storage.dart';
import '../schedules/push/push_providers.dart';

final secureTokenStorageProvider = Provider<SecureTokenStorage>((ref) {
  final config = ref.watch(appConfigProvider);
  final uri = config?.apiBaseUri;
  if (uri == null) return PlatformSecureTokenStorage();
  final client = createApiHttpClient(config);
  ref.onDispose(client.close);
  return RefreshingTokenStorage(
    storage: PlatformSecureTokenStorage(),
    baseUri: uri,
    client: client,
  );
});

final persistentSessionRepositoryProvider =
    Provider<PersistentSessionRepository?>((ref) {
      final tokenStorage = ref.watch(secureTokenStorageProvider);
      final db = ref.watch(storageDatabaseProvider);
      final wsService = ref.watch(workspaceStorageServiceProvider);

      if (!kIsWeb && (db == null || wsService == null)) return null;

      return PersistentSessionRepository(
        beforeSessionChange: () =>
            ref.read(pushRegistrationServiceProvider).detach(),
        tokenStorage: tokenStorage,
        database: db,
        workspaceStorageService: wsService,
      );
    });
