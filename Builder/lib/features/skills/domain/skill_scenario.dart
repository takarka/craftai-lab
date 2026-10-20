/// A user-authored workflow, distinct from assistant feature permissions.
/// This is declarative text: it cannot grant tools or execute uploaded code.
class SkillScenario {
  SkillScenario({
    required this.id,
    required this.name,
    required this.purpose,
    required List<String> requiredInputs,
    required List<String> steps,
    required this.outputFormat,
    List<String> constraints = const [],
    List<String> sources = const [],
    required List<String> qualityCriteria,
    this.revision = 1,
  }) : requiredInputs = List.unmodifiable(requiredInputs),
       steps = List.unmodifiable(steps),
       constraints = List.unmodifiable(constraints),
       sources = List.unmodifiable(sources),
       qualityCriteria = List.unmodifiable(qualityCriteria);

  final String id;
  final String name;
  final String purpose;
  final List<String> requiredInputs;
  final List<String> steps;
  final String outputFormat;
  final List<String> constraints;
  final List<String> sources;
  final List<String> qualityCriteria;
  final int revision;

  void validate() {
    if (id.trim().isEmpty ||
        id.length > 128 ||
        name.trim().isEmpty ||
        name.length > 120 ||
        purpose.trim().isEmpty ||
        outputFormat.trim().isEmpty ||
        steps.isEmpty ||
        qualityCriteria.isEmpty ||
        revision < 1) {
      throw ArgumentError(
        'Skill requires an ID, name, purpose, steps, output format and quality criteria',
      );
    }
    for (final values in [
      requiredInputs,
      steps,
      constraints,
      sources,
      qualityCriteria,
    ]) {
      if (values.any((value) => value.trim().isEmpty)) {
        throw ArgumentError('Skill fields must not contain blank entries');
      }
    }
    if (requiredInputs.map((s) => s.trim()).toSet().length !=
        requiredInputs.length) {
      throw ArgumentError('Required input names must be unique');
    }
    if (toJson().toString().length > 32000) {
      throw ArgumentError('Skill is too large');
    }
  }

  SkillScenario withRevision(int value) =>
      SkillScenario.fromJson({...toJson(), 'revision': value});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'purpose': purpose,
    'required_inputs': requiredInputs,
    'steps': steps,
    'output_format': outputFormat,
    'constraints': constraints,
    'sources': sources,
    'quality_criteria': qualityCriteria,
    'revision': revision,
  };

  factory SkillScenario.fromJson(Map<String, dynamic> json) => SkillScenario(
    id: json['id'] as String,
    name: json['name'] as String,
    purpose: json['purpose'] as String,
    requiredInputs: (json['required_inputs'] as List<dynamic>).cast<String>(),
    steps: (json['steps'] as List<dynamic>).cast<String>(),
    outputFormat: json['output_format'] as String,
    constraints: (json['constraints'] as List<dynamic>? ?? []).cast<String>(),
    sources: (json['sources'] as List<dynamic>? ?? []).cast<String>(),
    qualityCriteria: (json['quality_criteria'] as List<dynamic>).cast<String>(),
    revision: json['revision'] as int? ?? 1,
  );
}
