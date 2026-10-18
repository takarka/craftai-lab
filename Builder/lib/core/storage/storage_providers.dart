import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../features/onboarding/domain/initial_workspace_repository.dart';
import '../../features/onboarding/infrastructure/persistent_initial_workspace_repository.dart';
import 'database/storage_database.dart';
import 'security/secure_key_storage.dart';
import 'workspace/workspace_storage_service.dart';

final secureKeyStorageProvider = Provider<SecureKeyStorage>((ref) {
  return const PlatformSecureKeyStorage();
});

final installationIdProvider = Provider<String>((ref) {
  // Stable installation identifier per app installation
  return 'default_installation';
});

final databasePathProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return p.join(dir.path, 'craftai_builder.db');
});

final storageDatabaseProvider = Provider<StorageDatabase?>((ref) {
  final pathAsync = ref.watch(databasePathProvider);
  final path = pathAsync.asData?.value;
  if (path == null) return null;
  return StorageDatabase(databasePath: path);
});

final workspaceStorageServiceProvider = Provider<WorkspaceStorageService?>((
  ref,
) {
  final db = ref.watch(storageDatabaseProvider);
  if (db == null) return null;
  final keyStorage = ref.watch(secureKeyStorageProvider);
  final installationId = ref.watch(installationIdProvider);
  return WorkspaceStorageService(
    database: db,
    keyStorage: keyStorage,
    installationId: installationId,
  );
});

final persistentInitialWorkspaceRepositoryProvider =
    Provider<InitialWorkspaceRepository?>((ref) {
      final db = ref.watch(storageDatabaseProvider);
      if (db == null) return null;
      final installationId = ref.watch(installationIdProvider);
      return PersistentInitialWorkspaceRepository(
        database: db,
        installationId: installationId,
      );
    });
