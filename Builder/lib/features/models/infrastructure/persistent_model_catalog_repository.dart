import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../domain/model_catalog.dart';
import '../domain/model_category.dart';
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

  @override
  Future<ModelCategory> getSelectedCategory(String ownerId) async {
    if (database == null) return ModelCategory.standard;
    if (!database!.isOpen) {
      await database!.open();
    }

    final rows = await database!.db.query(
      StorageSchemaV1.tableAssistantConfigurations,
      columns: ['selected_category'],
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      limit: 1,
    );

    if (rows.isEmpty) return ModelCategory.standard;
    final catStr = rows.first['selected_category'] as String?;
    return ModelCategory.fromString(catStr);
  }

  @override
  Future<void> setSelectedCategory({
    required String ownerId,
    required ModelCategory category,
  }) async {
    if (database == null) return;
    if (!database!.isOpen) {
      await database!.open();
    }

    final nowUtc = DateTime.now().toUtc().toIso8601String();

    await database!.db.rawUpdate(
      '''
      UPDATE ${StorageSchemaV1.tableAssistantConfigurations}
      SET selected_category = ?,
          state_revision = state_revision + 1,
          updated_at_utc = ?
      WHERE owner_id = ?
    ''',
      [category.id, nowUtc, ownerId],
    );
  }
}

final class InMemoryModelCatalogRepository implements ModelCatalogRepository {
  InMemoryModelCatalogRepository({
    ModelCatalog? initialCatalog,
    Map<String, ModelCategory>? selections,
  }) : _catalog = initialCatalog ?? ModelCatalog.defaultCatalog(),
       _selections = selections ?? <String, ModelCategory>{};

  ModelCatalog _catalog;
  final Map<String, ModelCategory> _selections;

  void setCatalog(ModelCatalog catalog) => _catalog = catalog;

  @override
  Future<ModelCatalog> getCatalog({bool forceRefresh = false}) async {
    return _catalog;
  }

  @override
  Future<ModelCategory> getSelectedCategory(String ownerId) async {
    return _selections[ownerId] ?? ModelCategory.standard;
  }

  @override
  Future<void> setSelectedCategory({
    required String ownerId,
    required ModelCategory category,
  }) async {
    _selections[ownerId] = category;
  }
}
