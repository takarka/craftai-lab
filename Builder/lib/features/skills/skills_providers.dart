import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_providers.dart';
import '../assistant/infrastructure/persistent_assistant_repository.dart';
import '../assistant/assistant_providers.dart';
import 'domain/skill_scenario.dart';
import 'domain/skills_repository.dart';

final skillsRepositoryProvider = Provider<SkillsRepository?>((ref) {
  final database = ref.watch(storageDatabaseProvider);
  final workspace = ref.watch(workspaceStorageServiceProvider);
  if (database == null || workspace == null) return null;
  return PersistentAssistantRepository(
    database: database,
    workspaceService: workspace,
  );
});

final skillsListProvider = FutureProvider.family<List<SkillScenario>, String>((
  ref,
  ownerId,
) async {
  ref.watch(assistantConfigProvider(ownerId));
  final repository = ref.watch(skillsRepositoryProvider);
  if (repository == null) return [];
  return repository.getSkills(ownerId);
});

final skillsControllerProvider = Provider.family<SkillsController, String>(
  (ref, ownerId) => SkillsController(ref, ownerId),
);

class SkillsController {
  SkillsController(this.ref, this.ownerId);
  final Ref ref;
  final String ownerId;

  SkillsRepository get _repository =>
      ref.read(skillsRepositoryProvider) ??
      (throw StateError('Skills storage is unavailable'));

  Future<void> save(SkillScenario skill) async {
    await _repository.saveSkill(ownerId, skill);
    _refresh();
  }

  Future<void> delete(String skillId) async {
    await _repository.deleteSkill(ownerId, skillId);
    _refresh();
  }

  void _refresh() {
    if (!ref.mounted) return;
    ref.invalidate(skillsListProvider(ownerId));
    ref.invalidate(assistantConfigProvider(ownerId));
    ref.invalidate(assistantVersionsProvider(ownerId));
  }
}
