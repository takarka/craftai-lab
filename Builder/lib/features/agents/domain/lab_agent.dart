/// An immutable server configuration snapshot. Runtime data is never copied here.
class LabAgent {
  LabAgent(Map<String, dynamic> json) : json = Map.unmodifiable(json);

  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get name => json['name'] as String;
  String get taskType => json['task_type'] as String? ?? 'custom';
  String get subject => json['subject'] as String? ?? '';
  String get grade => json['grade'] as String? ?? '';
  String get instruction => json['instruction'] as String? ?? '';
  String? get modelId => json['model_id'] as String?;
  bool get allowSave => (json['permissions'] as Map?)?['save_material'] == true;
  bool get allowSearch =>
      (json['permissions'] as Map?)?['search_materials'] == true;
  int get epoch => json['epoch'] as int? ?? 0;
  int get version => json['version'] as int? ?? 1;
  DateTime? get updatedAt =>
      DateTime.tryParse(json['updated_at'] as String? ?? '');
}

class AgentsSnapshot {
  const AgentsSnapshot(this.agents, {this.offline = false});
  final List<LabAgent> agents;
  final bool offline;
}

class LabApiException implements Exception {
  const LabApiException(this.code, {this.status});
  final String code;
  final int? status;
  bool get isConnectionFailure => code == 'network.unavailable';
  @override
  String toString() => 'LabApiException($code)';
}
