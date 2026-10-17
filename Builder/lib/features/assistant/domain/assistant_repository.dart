import '../../models/domain/model_category.dart';
import 'assistant_config.dart';

abstract class AssistantRepository {
  /// Retrieves current assistant configuration for [ownerId].
  Future<AssistantConfig?> getConfiguration(String ownerId);

  /// Retrieves all versions for [ownerId], ordered by versionNumber descending.
  Future<List<AssistantVersion>> getVersions(String ownerId);

  /// Atomically commits changes to assistant configuration and creates a new version snapshot.
  Future<AssistantVersion> commitChange({
    required String ownerId,
    required String name,
    ModelCategory? selectedCategory,
    required Set<String> enabledSkills,
    List<String>? systemRules,
    required String reason,
  });

  /// Restores configuration from [targetVersionNumber].
  /// Skills in the snapshot not contained in [allowedSkills] are disabled (ADR-01/F09-08).
  Future<void> rollbackToVersion({
    required String ownerId,
    required int targetVersionNumber,
    required Set<String> allowedSkills,
  });

  /// Queries counts of local records for S15 data map.
  Future<LocalDataSummary> getLocalDataSummary(String ownerId);

  /// Gets retention days setting from teacher preferences.
  Future<int?> getStorageRetentionDays(String ownerId);

  /// Sets retention days setting in teacher preferences.
  Future<void> setStorageRetentionDays(String ownerId, int? days);

  /// Performs full assistant workspace reset (D05).
  /// Erases conversations, messages, facts, documents, versions and traces,
  /// resets assistant configuration, and advances workspace epoch.
  Future<void> resetAssistantWorkspace(String ownerId);
}
