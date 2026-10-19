import 'dart:convert';

import '../domain/skill_scenario.dart';

/// Render persisted skill requests as readable text; preserve ordinary messages.
String skillRequestSummary(String content, {required bool isKk}) {
  if (!content.startsWith('{') ||
      !content.contains('"builder_skill_request"')) {
    return content;
  }
  try {
    final json = jsonDecode(content) as Map<String, dynamic>;
    if (json['builder_skill_request'] != 1) return content;
    final skill = SkillScenario.fromJson(json['skill'] as Map<String, dynamic>);
    final inputs = (json['inputs'] as Map<String, dynamic>)
        .cast<String, String>();
    return [
      '${isKk ? 'Дағды' : 'Навык'}: ${skill.name}',
      skill.purpose,
      for (final entry in inputs.entries) '${entry.key}: ${entry.value}',
      '${isKk ? 'Қадамдар' : 'Шаги'}:',
      for (var i = 0; i < skill.steps.length; i++)
        '${i + 1}. ${skill.steps[i]}',
      '${isKk ? 'Нәтиже' : 'Результат'}: ${skill.outputFormat}',
      if (skill.constraints.isNotEmpty)
        '${isKk ? 'Шектеулер' : 'Ограничения'}: ${skill.constraints.join('; ')}',
      '${isKk ? 'Мәлімделген дереккөздер' : 'Заявленные источники'}: ${skill.sources.isEmpty ? (isKk ? 'жоқ' : 'нет') : skill.sources.join('; ')}',
      '${isKk ? 'Сапа өлшемдері' : 'Критерии качества'}: ${skill.qualityCriteria.join('; ')}',
    ].join('\n');
  } catch (_) {
    return content;
  }
}
