import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/schema/storage_schema_v1.dart';
import '../../core/storage/storage_providers.dart';
import '../chat/chat_providers.dart';
import '../models/model_providers.dart';
import '../onboarding/application/onboarding_controller.dart';
import 'domain/assistant_config.dart';
import 'domain/assistant_repository.dart';
import 'infrastructure/persistent_assistant_repository.dart';

final assistantRepositoryProvider = Provider<AssistantRepository?>((ref) {
  final db = ref.watch(storageDatabaseProvider);
  final ws = ref.watch(workspaceStorageServiceProvider);
  if (db == null || ws == null) return null;
  return PersistentAssistantRepository(database: db, workspaceService: ws);
});

final completedCourseLevelsProvider = FutureProvider.family<Set<int>, String>((ref, ownerId) async {
  final db = ref.watch(storageDatabaseProvider);
  if (db == null) return {1};
  if (!db.isOpen) await db.open();

  final rows = await db.db.query(
    StorageSchemaV1.tableCourseProgress,
    columns: ['level_id'],
    where: 'owner_id = ? AND is_completed = 1',
    whereArgs: [ownerId],
  );

  final completed = <int>{1}; // Level 1 is always unlocked
  for (final r in rows) {
    final lvl = int.tryParse(r['level_id'] as String);
    if (lvl != null) completed.add(lvl);
  }
  return completed;
});

final assistantConfigProvider = FutureProvider.family<AssistantConfig?, String>((ref, ownerId) async {
  final repo = ref.watch(assistantRepositoryProvider);
  if (repo == null) return null;
  return repo.getConfiguration(ownerId);
});

final assistantVersionsProvider = FutureProvider.family<List<AssistantVersion>, String>((ref, ownerId) async {
  // Re-read when config changes
  ref.watch(assistantConfigProvider(ownerId));
  final repo = ref.watch(assistantRepositoryProvider);
  if (repo == null) return [];
  return repo.getVersions(ownerId);
});

final localDataSummaryProvider = FutureProvider.family<LocalDataSummary, String>((ref, ownerId) async {
  final repo = ref.watch(assistantRepositoryProvider);
  if (repo == null) return const LocalDataSummary();
  return repo.getLocalDataSummary(ownerId);
});

final storageRetentionDaysProvider = FutureProvider.family<int?, String>((ref, ownerId) async {
  final repo = ref.watch(assistantRepositoryProvider);
  if (repo == null) return null;
  return repo.getStorageRetentionDays(ownerId);
});

final assistantControllerProvider = Provider.family<AssistantController, String>((ref, ownerId) {
  return AssistantController(ref: ref, ownerId: ownerId);
});

class AssistantController {
  AssistantController({required this.ref, required this.ownerId});

  final Ref ref;
  final String ownerId;

  AssistantRepository get _repo {
    final repo = ref.read(assistantRepositoryProvider);
    if (repo == null) throw StateError('AssistantRepository not available');
    return repo;
  }

  Future<void> saveName(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Имя не может быть пустым');
    }
    if (trimmed.runes.length > 30) {
      throw ArgumentError('Имя превышает 30 символов');
    }

    final currentConfig = await ref.read(assistantConfigProvider(ownerId).future);
    final selectedCat = ref.read(selectedCategoryProvider(ownerId));

    await _repo.commitChange(
      ownerId: ownerId,
      name: trimmed,
      selectedCategory: selectedCat,
      enabledSkills: currentConfig?.enabledSkills ?? {},
      systemRules: currentConfig?.systemRules,
      reason: 'Изменение имени на «$trimmed»',
    );

    ref.invalidate(assistantConfigProvider(ownerId));
    ref.invalidate(assistantVersionsProvider(ownerId));
    ref.invalidate(localDataSummaryProvider(ownerId));
  }

  Future<void> toggleSkill(AssistantSkillId skill, bool enable) async {
    if (skill.comingSoon) {
      throw StateError('Умение ${skill.title} пока недоступно');
    }

    final completedLevels = await ref.read(completedCourseLevelsProvider(ownerId).future);
    if (!completedLevels.contains(skill.level)) {
      throw StateError('Умение откроется на уровне ${skill.level}');
    }

    final currentConfig = await ref.read(assistantConfigProvider(ownerId).future);
    final currentSkills = Set<String>.from(currentConfig?.enabledSkills ?? {});

    if (enable) {
      currentSkills.add(skill.id);
    } else {
      currentSkills.remove(skill.id);
    }

    final selectedCat = ref.read(selectedCategoryProvider(ownerId));

    await _repo.commitChange(
      ownerId: ownerId,
      name: currentConfig?.name ?? '',
      selectedCategory: selectedCat,
      enabledSkills: currentSkills,
      systemRules: currentConfig?.systemRules,
      reason: '${enable ? "Включение" : "Отключение"} умения «${skill.title}»',
    );

    ref.invalidate(assistantConfigProvider(ownerId));
    ref.invalidate(assistantVersionsProvider(ownerId));
    ref.invalidate(localDataSummaryProvider(ownerId));
  }

  Future<void> manualSaveVersion(String? reason) async {
    final currentConfig = await ref.read(assistantConfigProvider(ownerId).future);
    final selectedCat = ref.read(selectedCategoryProvider(ownerId));

    final actualReason = (reason != null && reason.trim().isNotEmpty) ? reason.trim() : 'Ручное сохранение';

    await _repo.commitChange(
      ownerId: ownerId,
      name: currentConfig?.name ?? '',
      selectedCategory: selectedCat,
      enabledSkills: currentConfig?.enabledSkills ?? {},
      systemRules: currentConfig?.systemRules,
      reason: actualReason,
    );

    ref.invalidate(assistantConfigProvider(ownerId));
    ref.invalidate(assistantVersionsProvider(ownerId));
    ref.invalidate(localDataSummaryProvider(ownerId));
  }

  Future<void> saveInstructions({
    required List<String> systemRules,
    String? reason,
  }) async {
    final currentConfig = await ref.read(assistantConfigProvider(ownerId).future);
    final selectedCat = ref.read(selectedCategoryProvider(ownerId));
    final currentSkills = Set<String>.from(currentConfig?.enabledSkills ?? {});

    // Ensure instructions skill is enabled
    currentSkills.add(AssistantSkillId.instructions.id);

    final actualReason = (reason != null && reason.trim().isNotEmpty)
        ? reason.trim()
        : 'Обновлены инструкции ассистента';

    await _repo.commitChange(
      ownerId: ownerId,
      name: currentConfig?.name ?? '',
      selectedCategory: selectedCat,
      enabledSkills: currentSkills,
      systemRules: systemRules,
      reason: actualReason,
    );

    ref.invalidate(assistantConfigProvider(ownerId));
    ref.invalidate(assistantVersionsProvider(ownerId));
    ref.invalidate(localDataSummaryProvider(ownerId));
  }

  Future<void> rollbackToVersion(int targetVersionNumber) async {
    final completedLevels = await ref.read(completedCourseLevelsProvider(ownerId).future);
    final allowedSkills = AssistantSkillId.values
        .where((s) => !s.comingSoon && completedLevels.contains(s.level))
        .map((s) => s.id)
        .toSet();

    await _repo.rollbackToVersion(
      ownerId: ownerId,
      targetVersionNumber: targetVersionNumber,
      allowedSkills: allowedSkills,
    );

    // Refresh model category in models provider if restored
    final restoredConfig = await _repo.getConfiguration(ownerId);
    if (restoredConfig?.selectedCategory != null) {
      ref.read(selectedCategoryProvider(ownerId).notifier).select(restoredConfig!.selectedCategory!);
    }

    ref.invalidate(assistantConfigProvider(ownerId));
    ref.invalidate(assistantVersionsProvider(ownerId));
    ref.invalidate(localDataSummaryProvider(ownerId));
  }

  Future<void> undoLastChange() async {
    final versions = await ref.read(assistantVersionsProvider(ownerId).future);
    if (versions.length < 2) {
      throw StateError('Нет предыдущей версии для отмены');
    }

    // Sort by versionNumber descending
    final sorted = List<AssistantVersion>.from(versions)
      ..sort((a, b) => b.versionNumber.compareTo(a.versionNumber));

    final previousVersion = sorted[1];
    await rollbackToVersion(previousVersion.versionNumber);
  }

  Future<void> setRetentionDays(int? days) async {
    await _repo.setStorageRetentionDays(ownerId, days);
    ref.invalidate(storageRetentionDaysProvider(ownerId));
  }

  Future<void> resetWorkspace() async {
    // 1. Cancel in-flight chat message if any
    ref.read(chatSessionProvider(ownerId).notifier).stopGeneration();

    // 2. Perform database purge and epoch fence
    await _repo.resetAssistantWorkspace(ownerId);

    // 3. Invalidate all local caches and providers
    ref.invalidate(assistantConfigProvider(ownerId));
    ref.invalidate(assistantVersionsProvider(ownerId));
    ref.invalidate(localDataSummaryProvider(ownerId));
    ref.invalidate(chatSessionProvider(ownerId));
    ref.invalidate(completedCourseLevelsProvider(ownerId));

    // 4. Reset onboarding controller state to allow S03 setup
    ref.read(onboardingControllerProvider(ownerId).notifier).resetForRecreation();
  }
}
