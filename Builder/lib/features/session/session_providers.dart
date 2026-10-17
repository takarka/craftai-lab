import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/storage_providers.dart';
import 'infrastructure/persistent_session_repository.dart';
import 'infrastructure/secure_token_storage.dart';

final secureTokenStorageProvider = Provider<SecureTokenStorage>((ref) {
  return const PlatformSecureTokenStorage();
});

final persistentSessionRepositoryProvider = Provider<PersistentSessionRepository?>((ref) {
  final tokenStorage = ref.watch(secureTokenStorageProvider);
  final db = ref.watch(storageDatabaseProvider);
  final wsService = ref.watch(workspaceStorageServiceProvider);

  if (db == null || wsService == null) return null;

  return PersistentSessionRepository(
    tokenStorage: tokenStorage,
    database: db,
    workspaceStorageService: wsService,
  );
});
