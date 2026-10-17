import 'model_catalog.dart';
import 'model_category.dart';

abstract interface class ModelCatalogRepository {
  /// Retrieves the model catalog (cached locally or refreshed from network).
  Future<ModelCatalog> getCatalog({bool forceRefresh = false});

  /// Reads the selected model category for the given owner (stored in assistant_configurations).
  Future<ModelCategory> getSelectedCategory(String ownerId);

  /// Saves the selected model category for the given owner.
  Future<void> setSelectedCategory({
    required String ownerId,
    required ModelCategory category,
  });
}
