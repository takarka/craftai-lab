import 'package:flutter/material.dart';

import '../../../ui_kit/identity.dart';
import '../domain/course_topic.dart';

/// Storage IDs also identify the character's modules, independent of numbering.
class CourseCharacter extends StatelessWidget {
  const CourseCharacter({
    super.key,
    required this.completedLevels,
    this.size = 120,
    this.compact = false,
  });

  final Set<int> completedLevels;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final modules = CourseTopic.values
        .where((topic) => completedLevels.contains(topic.storageId))
        .map((topic) => topic.storageId)
        .toSet();
    final level = CourseTopic.highestCompletedOrder(modules);
    final isKk = Localizations.localeOf(context).languageCode == 'kk';
    return BuilderCharacter(
      size: size,
      compact: compact,
      unlockedModules: modules,
      semanticLabel: isKk
          ? 'ЖИ ассистенті, деңгей $level / 11, аяқталған тақырыптар: ${modules.length}'
          : 'ИИ-ассистент, уровень $level из 11, завершено тем: ${modules.length}',
    );
  }
}
