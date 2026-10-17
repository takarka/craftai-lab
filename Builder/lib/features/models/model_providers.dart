import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/storage/storage_providers.dart';
import '../session/session_providers.dart';
import 'domain/model_catalog.dart';
import 'domain/model_category.dart';
import 'domain/model_catalog_repository.dart';
import 'infrastructure/craft_ai_client.dart';
import 'infrastructure/persistent_model_catalog_repository.dart';

final craftAiClientProvider = Provider<CraftAiClient?>((ref) {
  final config = ref.watch(appConfigProvider);
  final uri = config?.apiBaseUri;
  if (uri == null) return null;

  final tokenStorage = ref.watch(secureTokenStorageProvider);
  return CraftAiClient(baseUri: uri, tokenStorage: tokenStorage);
});

final modelCatalogRepositoryProvider = Provider<ModelCatalogRepository>((ref) {
  final db = ref.watch(storageDatabaseProvider);
  final client = ref.watch(craftAiClientProvider);
  return PersistentModelCatalogRepository(database: db, client: client);
});

final modelCatalogFutureProvider = FutureProvider<ModelCatalog>((ref) async {
  final repo = ref.watch(modelCatalogRepositoryProvider);
  return await repo.getCatalog();
});

final selectedCategoryProvider = NotifierProvider.autoDispose
    .family<SelectedCategoryController, ModelCategory, String>(
      SelectedCategoryController.new,
    );

class SelectedCategoryController extends Notifier<ModelCategory> {
  SelectedCategoryController(this.ownerId);
  final String ownerId;

  @override
  ModelCategory build() {
    final repo = ref.watch(modelCatalogRepositoryProvider);
    repo.getSelectedCategory(ownerId).then((loaded) {
      state = loaded;
    });
    return ModelCategory.standard;
  }

  Future<void> select(ModelCategory category) async {
    state = category;
    final repo = ref.read(modelCatalogRepositoryProvider);
    await repo.setSelectedCategory(ownerId: ownerId, category: category);
  }
}
