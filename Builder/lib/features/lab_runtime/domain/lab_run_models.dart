class LabModelInfo {
  final String modelId;
  final bool available;
  final bool supportsTools;
  final bool supportsVision;

  const LabModelInfo({
    required this.modelId,
    this.available = true,
    this.supportsTools = false,
    this.supportsVision = false,
  });

  factory LabModelInfo.fromJson(Map<String, dynamic> json) {
    return LabModelInfo(
      modelId: (json['model_id'] as String?) ?? '',
      available: (json['available'] as bool?) ?? false,
      supportsTools: (json['supports_tools'] as bool?) ?? false,
      supportsVision: (json['supports_vision'] as bool?) ?? false,
    );
  }
}

class LabRunEvent {
  final String id;
  final int sequence;
  final int epoch;
  final String eventType;
  final Map<String, dynamic> payload;
  final String createdAtUtc;

  const LabRunEvent({
    required this.id,
    required this.sequence,
    required this.epoch,
    required this.eventType,
    required this.payload,
    required this.createdAtUtc,
  });

  factory LabRunEvent.fromJson(Map<String, dynamic> json) {
    return LabRunEvent(
      id: (json['id'] as String?) ?? '',
      sequence: (json['sequence'] as int?) ?? 0,
      epoch: (json['epoch'] as int?) ?? 0,
      eventType: (json['event_type'] as String?) ?? '',
      payload: Map<String, dynamic>.from(
        (json['payload'] as Map?) ?? const <String, dynamic>{},
      ),
      createdAtUtc: (json['created_at_utc'] as String?) ?? '',
    );
  }
}

class LabPendingAction {
  final String id;
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> params;
  final String paramsHash;
  final String status;
  final String expiresAtUtc;

  const LabPendingAction({
    required this.id,
    required this.toolCallId,
    required this.toolName,
    required this.params,
    required this.paramsHash,
    required this.status,
    required this.expiresAtUtc,
  });

  factory LabPendingAction.fromJson(Map<String, dynamic> json) {
    return LabPendingAction(
      id: (json['id'] as String?) ?? '',
      toolCallId: (json['tool_call_id'] as String?) ?? '',
      toolName: (json['tool_name'] as String?) ?? '',
      params: Map<String, dynamic>.from(
        (json['params'] as Map?) ?? const <String, dynamic>{},
      ),
      paramsHash: (json['params_hash'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'pending',
      expiresAtUtc: (json['expires_at_utc'] as String?) ?? '',
    );
  }
}

class LabRun {
  final String id;
  final String agentId;
  final String agentVersionId;
  final int epoch;
  final String modelId;
  final String status;
  final String? stopReason;
  final String? finalOutput;
  final int toolCallsCount;
  final int activeElapsedMs;
  final List<LabRunEvent> events;
  final List<LabPendingAction> pendingActions;

  const LabRun({
    required this.id,
    required this.agentId,
    required this.agentVersionId,
    required this.epoch,
    required this.modelId,
    required this.status,
    this.stopReason,
    this.finalOutput,
    this.toolCallsCount = 0,
    this.activeElapsedMs = 0,
    this.events = const [],
    this.pendingActions = const [],
  });

  LabPendingAction? get activePendingAction {
    for (final a in pendingActions) {
      if (a.status == 'pending') return a;
    }
    return null;
  }

  factory LabRun.fromJson(Map<String, dynamic> json) {
    final rawEvents = (json['events'] as List?) ?? const [];
    final rawActions = (json['pending_actions'] as List?) ?? const [];
    return LabRun(
      id: (json['id'] as String?) ?? '',
      agentId: (json['agent_id'] as String?) ?? '',
      agentVersionId: (json['agent_version_id'] as String?) ?? '',
      epoch: (json['epoch'] as int?) ?? 0,
      modelId: (json['model_id'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'running',
      stopReason: json['stop_reason'] as String?,
      finalOutput: json['final_output'] as String?,
      toolCallsCount: (json['tool_calls_count'] as int?) ?? 0,
      activeElapsedMs: (json['active_elapsed_ms'] as int?) ?? 0,
      events: rawEvents
          .whereType<Map>()
          .map((e) => LabRunEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      pendingActions: rawActions
          .whereType<Map>()
          .map((a) => LabPendingAction.fromJson(Map<String, dynamic>.from(a)))
          .toList(),
    );
  }
}

class LabMaterialItem {
  final String id;
  final String agentId;
  final String title;
  final String content;
  final String source;
  final String createdAtUtc;

  const LabMaterialItem({
    required this.id,
    required this.agentId,
    required this.title,
    required this.content,
    required this.source,
    required this.createdAtUtc,
  });

  factory LabMaterialItem.fromJson(Map<String, dynamic> json) {
    return LabMaterialItem(
      id: (json['id'] as String?) ?? '',
      agentId: (json['agent_id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      source: (json['source'] as String?) ?? 'text',
      createdAtUtc: (json['created_at_utc'] as String?) ?? '',
    );
  }
}

class LabPhotoExtraction {
  final String photoId;
  final String extractedText;
  final String expiresAtUtc;

  const LabPhotoExtraction({
    required this.photoId,
    required this.extractedText,
    required this.expiresAtUtc,
  });

  factory LabPhotoExtraction.fromJson(Map<String, dynamic> json) {
    return LabPhotoExtraction(
      photoId: (json['photo_id'] as String?) ?? '',
      extractedText: (json['extracted_text'] as String?) ?? '',
      expiresAtUtc: (json['expires_at_utc'] as String?) ?? '',
    );
  }
}

class LabMemoryItem {
  final String id;
  final String agentId;
  final String content;
  final String createdAtUtc;

  const LabMemoryItem({
    required this.id,
    required this.agentId,
    required this.content,
    required this.createdAtUtc,
  });

  factory LabMemoryItem.fromJson(Map<String, dynamic> json) {
    return LabMemoryItem(
      id: (json['id'] as String?) ?? '',
      agentId: (json['agent_id'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      createdAtUtc: (json['created_at_utc'] as String?) ?? '',
    );
  }
}

class LabSkillItem {
  final String slug;
  final String title;
  final String version;
  final String baseContent;
  final bool enabled;
  final String overrideText;
  final int revision;
  final List<String> collisions;

  const LabSkillItem({
    required this.slug,
    required this.title,
    required this.version,
    required this.baseContent,
    required this.enabled,
    required this.overrideText,
    required this.revision,
    this.collisions = const [],
  });

  factory LabSkillItem.fromJson(Map<String, dynamic> json) {
    return LabSkillItem(
      slug: (json['slug'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      version: (json['version'] as String?) ?? '1.0.0',
      baseContent: (json['base_content'] as String?) ?? '',
      enabled: (json['enabled'] as bool?) ?? false,
      overrideText: (json['override_text'] as String?) ?? '',
      revision: (json['revision'] as int?) ?? 0,
      collisions: ((json['collisions'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class LabApiException implements Exception {
  final String code;
  final String message;
  final String nextStep;
  final bool isOffline;

  const LabApiException({
    required this.code,
    required this.message,
    this.nextStep = 'Проверьте подключение и повторите попытку.',
    this.isOffline = false,
  });
}
