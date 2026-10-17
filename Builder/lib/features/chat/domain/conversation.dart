enum RetentionPolicy {
  persistent,
  ephemeral;

  static RetentionPolicy fromString(String? value) {
    if (value == 'ephemeral') return RetentionPolicy.ephemeral;
    return RetentionPolicy.persistent;
  }

  String toDbValue() => name;
}

class Conversation {
  final String id;
  final String ownerId;
  final String title;
  final DateTime createdAtUtc;
  final DateTime activityAtUtc;
  final RetentionPolicy retentionPolicy;

  const Conversation({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.createdAtUtc,
    required this.activityAtUtc,
    this.retentionPolicy = RetentionPolicy.persistent,
  });

  bool get isEphemeral => retentionPolicy == RetentionPolicy.ephemeral;

  Conversation copyWith({
    String? title,
    DateTime? activityAtUtc,
    RetentionPolicy? retentionPolicy,
  }) {
    return Conversation(
      id: id,
      ownerId: ownerId,
      title: title ?? this.title,
      createdAtUtc: createdAtUtc,
      activityAtUtc: activityAtUtc ?? this.activityAtUtc,
      retentionPolicy: retentionPolicy ?? this.retentionPolicy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'title': title,
      'created_at_utc': createdAtUtc.toIso8601String(),
      'activity_at_utc': activityAtUtc.toIso8601String(),
      'retention_policy': retentionPolicy.toDbValue(),
    };
  }

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      title: map['title'] as String,
      createdAtUtc: DateTime.parse(map['created_at_utc'] as String),
      activityAtUtc: DateTime.parse(map['activity_at_utc'] as String),
      retentionPolicy: RetentionPolicy.fromString(map['retention_policy'] as String?),
    );
  }
}
