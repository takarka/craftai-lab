import 'memory_models.dart';

/// Repository interface for persistent memory facts and candidate suggestions (F13-01..F13-08).
abstract class MemoryRepository {
  /// Fetches saved facts for the given workspace owner.
  Future<List<MemoryFact>> getFacts({
    required String ownerId,
    bool? enabledOnly,
  });

  /// Adds a new fact to persistent memory.
  Future<MemoryFact> addFact({
    required String ownerId,
    required String factText,
    MemoryFactSource source = MemoryFactSource.manual,
  });

  /// Updates the text of an existing fact.
  Future<MemoryFact> updateFact({
    required String id,
    required String factText,
  });

  /// Toggles whether a fact is enabled for context injection.
  Future<void> toggleFact({
    required String id,
    required bool isEnabled,
  });

  /// Physically deletes a fact from storage (ADR-02).
  Future<void> deleteFact({
    required String id,
    required String ownerId,
  });

  /// Returns candidate/suggested facts proposed by the assistant for teacher review (F13-03).
  Future<List<MemoryCandidateFact>> getSuggestedFacts({
    required String ownerId,
  });

  /// Adds a candidate fact proposal.
  Future<MemoryCandidateFact> addSuggestedFact({
    required String ownerId,
    required String factText,
    String? rationale,
  });

  /// Dismisses / rejects a candidate proposal without saving it (F13-03).
  Future<void> dismissSuggestedFact({
    required String ownerId,
    required String candidateId,
  });

  /// Accepts a candidate proposal, saving it as an active MemoryFact (source: suggested) (F13-03).
  Future<MemoryFact> acceptSuggestedFact({
    required String ownerId,
    required String candidateId,
  });

  /// Loads 3 educational presets for Level 4 practice (F13-07):
  /// 1. «В 7 «Б» классе 24 ученика»
  /// 2. «Длительность одного урока составляет 40 минут»
  /// 3. «Профильный предмет класса — углубленная математика»
  Future<List<MemoryFact>> loadEducationalPracticePresets({
    required String ownerId,
  });
}
