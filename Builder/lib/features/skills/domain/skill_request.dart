import 'dart:convert';

import 'skill_scenario.dart';

/// The immutable scenario and inputs actually included in a user request.
/// Reading a request does not resolve sources or execute its steps.
class SkillRequest {
  SkillRequest._(this.skill, Map<String, String> inputs)
    : inputs = Map.unmodifiable(inputs);
  final SkillScenario skill;
  final Map<String, String> inputs;

  static SkillRequest? tryParse(String content) {
    if (!content.startsWith('{') ||
        !content.contains('"builder_skill_request"')) {
      return null;
    }
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      if (json['builder_skill_request'] != 1) return null;
      final skill = SkillScenario.fromJson(
        json['skill'] as Map<String, dynamic>,
      );
      skill.validate();
      final inputs = (json['inputs'] as Map<String, dynamic>)
          .cast<String, String>();
      if (skill.requiredInputs.any(
        (key) => inputs[key]?.trim().isNotEmpty != true,
      )) {
        return null;
      }
      return SkillRequest._(skill, inputs);
    } catch (_) {
      return null;
    }
  }
}
