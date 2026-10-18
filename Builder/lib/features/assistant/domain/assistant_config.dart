import '../../models/domain/model_category.dart';
import '../../../ui_kit/identity.dart';

enum AssistantSkillId {
  instructions(
    id: 'instructions',
    level: 2,
    title: 'Инструкции',
    subtitle: 'Правила поведения и тон общения',
    glyph: BuilderGlyph.doc,
    comingSoon: false,
  ),
  knowledge(
    id: 'knowledge',
    level: 3,
    title: 'Знания (RAG)',
    subtitle: 'Поиск по вашим учебным материалам',
    glyph: BuilderGlyph.doc,
    comingSoon: false,
  ),
  memory(
    id: 'memory',
    level: 4,
    title: 'Память',
    subtitle: 'Факты о ваших классах и предпочтениях',
    glyph: BuilderGlyph.memory,
    comingSoon: false,
  ),
  tools(
    id: 'tools',
    level: 5,
    title: 'Инструменты и MCP',
    subtitle: 'Календарь, поиск и внешние сервисы',
    glyph: BuilderGlyph.tool,
    comingSoon: false,
  ),
  voice(
    id: 'voice',
    level: 6,
    title: 'Голос',
    subtitle: 'Голосовой ввод и озвучивание ответов',
    glyph: BuilderGlyph.phone,
    comingSoon: true,
  ),
  vision(
    id: 'vision',
    level: 7,
    title: 'Зрение',
    subtitle: 'Распознавание заданий с фото и сканов',
    glyph: BuilderGlyph.search,
    comingSoon: true,
  ),
  security(
    id: 'security',
    level: 8,
    title: 'Безопасность',
    subtitle: 'Проверка ответов и защита данных',
    glyph: BuilderGlyph.lock,
    comingSoon: true,
  ),
  agent(
    id: 'agent',
    level: 9,
    title: 'Агент',
    subtitle: 'Автономное планирование и цепочки действий',
    glyph: BuilderGlyph.bolt,
    comingSoon: true,
  );

  const AssistantSkillId({
    required this.id,
    required this.level,
    required this.title,
    required this.subtitle,
    required this.glyph,
    required this.comingSoon,
  });

  final String id;
  final int level;
  final String title;
  final String subtitle;
  final BuilderGlyph glyph;
  final bool comingSoon;

  static AssistantSkillId? fromId(String id) {
    for (final skill in values) {
      if (skill.id == id) return skill;
    }
    return null;
  }
}

class AssistantSnapshot {
  const AssistantSnapshot({
    required this.name,
    this.selectedCategory,
    this.enabledSkills = const {},
    this.systemRules = const [],
    this.memoryFactsCount = 0,
    this.documentsCount = 0,
    this.documentIds = const [],
  });

  final String name;
  final ModelCategory? selectedCategory;
  final Set<String> enabledSkills;
  final List<String> systemRules;
  final int memoryFactsCount;
  final int documentsCount;
  final List<String> documentIds;

  Map<String, dynamic> toJson() => {
    'name': name,
    'selected_category': selectedCategory?.name,
    'enabled_skills': enabledSkills.toList()..sort(),
    'system_rules': systemRules,
    'memory_facts_count': memoryFactsCount,
    'documents_count': documentsCount,
    'document_ids': documentIds,
  };

  factory AssistantSnapshot.fromJson(Map<String, dynamic> json) {
    final catName = json['selected_category'] as String?;
    final cat = catName != null ? ModelCategory.fromString(catName) : null;
    final skillsRaw = json['enabled_skills'] as List<dynamic>? ?? [];
    final rulesRaw = json['system_rules'] as List<dynamic>? ?? [];
    final docsRaw = json['document_ids'] as List<dynamic>? ?? [];

    return AssistantSnapshot(
      name: json['name'] as String? ?? '',
      selectedCategory: cat,
      enabledSkills: skillsRaw.map((e) => e.toString()).toSet(),
      systemRules: rulesRaw.map((e) => e.toString()).toList(),
      memoryFactsCount: json['memory_facts_count'] as int? ?? 0,
      documentsCount: json['documents_count'] as int? ?? 0,
      documentIds: docsRaw.map((e) => e.toString()).toList(),
    );
  }
}

class AssistantVersion {
  const AssistantVersion({
    required this.versionNumber,
    required this.createdAtUtc,
    required this.reason,
    required this.snapshot,
    this.parentId,
    this.schemaVersion = 1,
    this.isCurrent = false,
    this.missingResources = const [],
  });

  final int versionNumber;
  final DateTime createdAtUtc;
  final String reason;
  final AssistantSnapshot snapshot;
  final String? parentId;
  final int schemaVersion;
  final bool isCurrent;
  final List<String> missingResources;

  AssistantVersion copyWith({bool? isCurrent, List<String>? missingResources}) {
    return AssistantVersion(
      versionNumber: versionNumber,
      createdAtUtc: createdAtUtc,
      reason: reason,
      snapshot: snapshot,
      parentId: parentId,
      schemaVersion: schemaVersion,
      isCurrent: isCurrent ?? this.isCurrent,
      missingResources: missingResources ?? this.missingResources,
    );
  }
}

class AssistantConfig {
  const AssistantConfig({
    required this.ownerId,
    required this.name,
    this.selectedCategory,
    this.enabledSkills = const {},
    this.systemRules = const [],
    this.stateRevision = 1,
    required this.updatedAtUtc,
  });

  final String ownerId;
  final String name;
  final ModelCategory? selectedCategory;
  final Set<String> enabledSkills;
  final List<String> systemRules;
  final int stateRevision;
  final DateTime updatedAtUtc;

  AssistantConfig copyWith({
    String? name,
    ModelCategory? selectedCategory,
    Set<String>? enabledSkills,
    List<String>? systemRules,
    int? stateRevision,
    DateTime? updatedAtUtc,
  }) {
    return AssistantConfig(
      ownerId: ownerId,
      name: name ?? this.name,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      enabledSkills: enabledSkills ?? this.enabledSkills,
      systemRules: systemRules ?? this.systemRules,
      stateRevision: stateRevision ?? this.stateRevision,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }
}

class LocalDataSummary {
  const LocalDataSummary({
    this.conversationsCount = 0,
    this.messagesCount = 0,
    this.memoryFactsCount = 0,
    this.documentsCount = 0,
    this.chunksCount = 0,
    this.tracesCount = 0,
    this.versionsCount = 0,
  });

  final int conversationsCount;
  final int messagesCount;
  final int memoryFactsCount;
  final int documentsCount;
  final int chunksCount;
  final int tracesCount;
  final int versionsCount;
}
