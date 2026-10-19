import 'skill_scenario.dart';

abstract interface class SkillsRepository {
  Future<List<SkillScenario>> getSkills(String ownerId);

  /// Saves the scenario and an assistant version in the same transaction.
  Future<void> saveSkill(String ownerId, SkillScenario skill);

  /// Deletes only this owner's scenario and records the new assistant version.
  Future<void> deleteSkill(String ownerId, String skillId);
}
