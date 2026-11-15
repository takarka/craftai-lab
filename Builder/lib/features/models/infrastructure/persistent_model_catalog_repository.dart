import '../../../core/storage/database/storage_database.dart';
import '../domain/model_catalog.dart';
import '../domain/model_catalog_repository.dart';
import 'craft_ai_client.dart';

final class PersistentModelCatalogRepository implements ModelCatalogRepository {
  PersistentModelCatalogRepository({this.database, this.client});

  final StorageDatabase? database;
  final CraftAiClient? client;

  ModelCatalog? _cachedCatalog;

  @override
  Future<ModelCatalog> getCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedCatalog != null) {
      return _cachedCatalog!;
    }

    // Try fetching from network if client is provided
    if (client != null) {
      try {
        final json = await client!.getJson('/builder/models');
        if (json.isNotEmpty) {
          final catalog = ModelCatalog.fromJson(json);
          _cachedCatalog = catalog;
          return catalog;
        }
      } catch (_) {
        // Offline or server issue: fall back gracefully to local cache or defaults
      }
    }

    if (_cachedCatalog != null) {
      return _cachedCatalog!;
    }

    // Default offline catalog
    final fallback = ModelCatalog.defaultCatalog();
    _cachedCatalog = fallback;
    return fallback;
  }
}

final class InMemoryModelCatalogRepository implements ModelCatalogRepository {
  InMemoryModelCatalogRepository({ModelCatalog? initialCatalog})
    : _catalog = initialCatalog ?? ModelCatalog.defaultCatalog();

  ModelCatalog _catalog;

  void setCatalog(ModelCatalog catalog) => _catalog = catalog;

  @override
  Future<ModelCatalog> getCatalog({bool forceRefresh = false}) async {
    return _catalog;
  }
}
