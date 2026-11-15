import 'model_catalog.dart';

abstract interface class ModelCatalogRepository {
  /// Retrieves the model catalog (cached locally or refreshed from network).
  Future<ModelCatalog> getCatalog({bool forceRefresh = false});
}
