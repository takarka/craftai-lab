import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_providers.dart';
import '../domain/memory_models.dart';
import '../domain/memory_repository.dart';
import '../infrastructure/persistent_memory_repository.dart';

/// Global provider for the memory repository.
final memoryRepositoryProvider = Provider<MemoryRepository>((ref) {
  final db = ref.watch(storageDatabaseProvider);
  if (db == null) return InMemoryMemoryRepository();
  return PersistentMemoryRepository(database: db);
});

/// UI State for Screen S42 (Memory and Classroom Facts).
class MemoryState {
  final List<MemoryFact> facts;
  final List<MemoryCandidateFact> candidateFacts;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  const MemoryState({
    this.facts = const [],
    this.candidateFacts = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
  });

  MemoryState copyWith({
    List<MemoryFact>? facts,
    List<MemoryCandidateFact>? candidateFacts,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
  }) {
    return MemoryState(
      facts: facts ?? this.facts,
      candidateFacts: candidateFacts ?? this.candidateFacts,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage,
    );
  }
}

/// Controller for managing facts and candidate suggestions in S42.
class MemoryNotifier extends Notifier<MemoryState> {
  final String ownerId;

  MemoryNotifier(this.ownerId);

  @override
  MemoryState build() {
    Future.microtask(() => load());
    return const MemoryState(isLoading: true);
  }

  MemoryRepository get _repo => ref.read(memoryRepositoryProvider);

  Future<void> load() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final facts = await _repo.getFacts(ownerId: ownerId);
      final candidates = await _repo.getSuggestedFacts(ownerId: ownerId);
      state = state.copyWith(
        facts: facts,
        candidateFacts: candidates,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Ошибка загрузки фактов памяти: $e',
      );
    }
  }

  Future<MemoryFact?> addFact(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final fact = await _repo.addFact(
        ownerId: ownerId,
        factText: trimmed,
        source: MemoryFactSource.manual,
      );
      state = state.copyWith(
        facts: [...state.facts, fact],
        isSaving: false,
      );
      return fact;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Не удалось сохранить факт: $e',
      );
      return null;
    }
  }

  Future<void> updateFact(String id, String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;

    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final updated = await _repo.updateFact(id: id, factText: trimmed);
      state = state.copyWith(
        facts: state.facts.map((f) => f.id == id ? updated : f).toList(),
        isSaving: false,
      );
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Не удалось обновить факт: $e',
      );
    }
  }

  Future<void> toggleFact(String id, bool isEnabled) async {
    try {
      await _repo.toggleFact(id: id, isEnabled: isEnabled);
      state = state.copyWith(
        facts: state.facts
            .map((f) => f.id == id ? f.copyWith(isEnabled: isEnabled) : f)
            .toList(),
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Ошибка переключения: $e');
    }
  }

  Future<void> deleteFact(String id) async {
    try {
      await _repo.deleteFact(id: id, ownerId: ownerId);
      state = state.copyWith(
        facts: state.facts.where((f) => f.id != id).toList(),
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Ошибка удаления: $e');
    }
  }

  Future<void> acceptSuggested(String candidateId) async {
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final fact = await _repo.acceptSuggestedFact(
        ownerId: ownerId,
        candidateId: candidateId,
      );
      state = state.copyWith(
        facts: [...state.facts, fact],
        candidateFacts: state.candidateFacts.where((c) => c.id != candidateId).toList(),
        isSaving: false,
      );
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Ошибка сохранения предложенного факта: $e',
      );
    }
  }

  Future<void> dismissSuggested(String candidateId) async {
    try {
      await _repo.dismissSuggestedFact(
        ownerId: ownerId,
        candidateId: candidateId,
      );
      state = state.copyWith(
        candidateFacts: state.candidateFacts.where((c) => c.id != candidateId).toList(),
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Ошибка отклонения: $e');
    }
  }

  Future<void> loadEducationalPresets() async {
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final presets = await _repo.loadEducationalPracticePresets(ownerId: ownerId);
      state = state.copyWith(
        facts: [...state.facts, ...presets],
        isSaving: false,
      );
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Не удалось загрузить учебные пресеты: $e',
      );
    }
  }
}

/// Provider for S42 Memory page state by ownerId.
final memoryControllerProvider =
    NotifierProvider.family<MemoryNotifier, MemoryState, String>(
  (arg) => MemoryNotifier(arg),
);
