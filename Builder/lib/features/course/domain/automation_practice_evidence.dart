/// Evidence describes server history, not proof of device notification delivery.
class AutomationTemplateEvidence {
  const AutomationTemplateEvidence({
    required this.template,
    this.scheduleId,
    this.manualRun,
    this.scheduledRun,
  });
  final String template;
  final String? scheduleId;
  final Map<String, dynamic>? manualRun;
  final Map<String, dynamic>? scheduledRun;
  bool get hasManualResult => manualRun != null;
  bool get hasScheduledResult => scheduledRun != null;

  static AutomationTemplateEvidence fromHistory(
    String template,
    Map<String, dynamic> schedule,
    List<Map<String, dynamic>> runs,
  ) {
    Map<String, dynamic>? find(String trigger) {
      final candidates =
          runs.where((run) {
            if (run['scheduleId'] != schedule['id'] ||
                run['trigger'] != trigger ||
                run['status'] != 'succeeded') {
              return false;
            }
            final result = run['result'];
            if (result is! Map ||
                run['id'] is! String ||
                (run['id'] as String).isEmpty) {
              return false;
            }
            final sections = result['sections'];
            if (sections is! List ||
                !sections.any(
                  (s) =>
                      s is Map &&
                      s['items'] is List &&
                      (s['items'] as List).any(
                        (v) => v is String && v.trim().isNotEmpty,
                      ),
                )) {
              return false;
            }
            if (DateTime.tryParse('${result['dataSnapshotAtUtc']}') == null ||
                DateTime.tryParse('${result['generatedAtUtc']}') == null) {
              return false;
            }
            if (template == 'daily-brief') {
              final sources = result['sources'];
              if (sources is! List ||
                  !sources.any((s) => s is Map && s['type'] == 'calendar')) {
                return false;
              }
            }
            return true;
          }).toList()..sort(
            (a, b) =>
                DateTime.parse(
                  (b['result'] as Map)['generatedAtUtc'] as String,
                ).compareTo(
                  DateTime.parse(
                    (a['result'] as Map)['generatedAtUtc'] as String,
                  ),
                ),
          );
      return candidates.isEmpty ? null : candidates.first;
    }

    return AutomationTemplateEvidence(
      template: template,
      scheduleId: schedule['id'] as String,
      manualRun: find('manual'),
      scheduledRun: find('scheduled'),
    );
  }
}
