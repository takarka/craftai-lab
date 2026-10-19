/// Topic identity is independent of the curriculum's visible numbering.
/// Existing storage and route keys remain unchanged during the 9 → 11 upgrade.
enum CourseTopic {
  introduction(1, 1),
  instructions(2, 2),
  skills(10, 3),
  knowledge(3, 4),
  memory(4, 5),
  tools(5, 6),
  automation(11, 7),
  voice(6, 8),
  vision(7, 9),
  security(8, 10),
  agent(9, 11);

  const CourseTopic(this.storageId, this.displayOrder);

  final int storageId;
  final int displayOrder;

  String get contentId => 'course.topic.$name';

  /// Topics with a working lesson, in the order a learner passes them.
  /// Each one unlocks after the previous one in this list.
  static const List<CourseTopic> enabledSequence = [
    introduction,
    instructions,
    skills,
    knowledge,
    memory,
    tools,
  ];

  bool get isEnabled => enabledSequence.contains(this);

  CourseTopic? get prerequisite {
    final index = enabledSequence.indexOf(this);
    return index > 0 ? enabledSequence[index - 1] : null;
  }

  CourseTopic? get next {
    final index = enabledSequence.indexOf(this);
    return index >= 0 && index < enabledSequence.length - 1
        ? enabledSequence[index + 1]
        : null;
  }

  static bool isEnabledStorageId(int id) {
    for (final topic in enabledSequence) {
      if (topic.storageId == id) return true;
    }
    return false;
  }

  static CourseTopic fromStorageId(int id) => values.firstWhere(
    (topic) => topic.storageId == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown course topic'),
  );
}
