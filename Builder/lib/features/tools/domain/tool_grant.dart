/// Persistent tool authorization grant stored in SQLite (tableToolGrants) (F14-01, F14-02).
class ToolGrant {
  final String ownerId;
  final String toolName;
  final bool isEnabled;
  final String permissionScope;
  final int revision;
  final DateTime updatedAtUtc;

  const ToolGrant({
    required this.ownerId,
    required this.toolName,
    this.isEnabled = false,
    this.permissionScope = 'standard',
    this.revision = 1,
    required this.updatedAtUtc,
  });

  ToolGrant copyWith({
    String? ownerId,
    String? toolName,
    bool? isEnabled,
    String? permissionScope,
    int? revision,
    DateTime? updatedAtUtc,
  }) {
    return ToolGrant(
      ownerId: ownerId ?? this.ownerId,
      toolName: toolName ?? this.toolName,
      isEnabled: isEnabled ?? this.isEnabled,
      permissionScope: permissionScope ?? this.permissionScope,
      revision: revision ?? this.revision,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'owner_id': ownerId,
      'tool_name': toolName,
      'is_enabled': isEnabled ? 1 : 0,
      'permission_scope': permissionScope,
      'revision': revision,
      'updated_at_utc': updatedAtUtc.toIso8601String(),
    };
  }

  factory ToolGrant.fromMap(Map<String, dynamic> map) {
    return ToolGrant(
      ownerId: map['owner_id'] as String,
      toolName: map['tool_name'] as String,
      isEnabled: (map['is_enabled'] as int? ?? 0) == 1,
      permissionScope: map['permission_scope'] as String? ?? 'standard',
      revision: map['revision'] as int? ?? 1,
      updatedAtUtc: DateTime.tryParse(map['updated_at_utc'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}
