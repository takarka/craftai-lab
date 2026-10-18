import 'instruction_models.dart';

abstract class InstructionsRepository {
  Future<InstructionConfig> getInstructionConfig(String ownerId);
  Future<void> saveInstructionConfig(String ownerId, InstructionConfig config);
  Future<void> addCustomRule(String ownerId, InstructionRule rule);
  Future<void> deleteCustomRule(String ownerId, String ruleId);
  Future<void> resetToDefaults(String ownerId);
}
