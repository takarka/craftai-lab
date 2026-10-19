import 'package:builder/features/course/domain/automation_practice_evidence.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> run({
  String id = 'r1',
  String trigger = 'manual',
  String status = 'succeeded',
  String scheduleId = 's1',
  String delivery = 'failed',
}) => {
  'id': id,
  'scheduleId': scheduleId,
  'trigger': trigger,
  'status': status,
  'delivery': delivery,
  'result': {
    'generatedAtUtc': '2026-10-19T03:00:00Z',
    'dataSnapshotAtUtc': '2026-10-19T02:59:00Z',
    'sections': [
      {
        'title': 'План дня',
        'items': ['Урок в 09:00'],
      },
    ],
    'sources': [
      {'type': 'calendar', 'label': 'Календарь Builder'},
    ],
    'gaps': [],
  },
};

void main() {
  const schedule = {'id': 's1', 'template': 'daily-brief'};
  test('manual result never proves a scheduled run; delivery is separate', () {
    final evidence = AutomationTemplateEvidence.fromHistory(
      'daily-brief',
      schedule,
      [run()],
    );
    expect(evidence.hasManualResult, isTrue);
    expect(evidence.hasScheduledResult, isFalse);
    final both = AutomationTemplateEvidence.fromHistory(
      'daily-brief',
      schedule,
      [run(), run(id: 'r2', trigger: 'scheduled')],
    );
    expect(both.hasScheduledResult, isTrue);
    expect(both.manualRun!['id'], isNot(both.scheduledRun!['id']));
  });
  test(
    'wrong schedule and failed or queued runs do not prove completion even with old result',
    () {
      final evidence =
          AutomationTemplateEvidence.fromHistory('daily-brief', schedule, [
            run(scheduleId: 'another-owner-schedule'),
            run(status: 'failed'),
            run(status: 'queued', trigger: 'scheduled'),
          ]);
      expect(evidence.hasManualResult, isFalse);
      expect(evidence.hasScheduledResult, isFalse);
    },
  );
  test(
    'missing timestamp, empty output or missing calendar source is incomplete evidence',
    () {
      for (final field in ['generatedAtUtc', 'sections', 'sources']) {
        final incomplete = run();
        final result = incomplete['result'] as Map;
        result[field] = field == 'generatedAtUtc' ? null : [];
        expect(
          AutomationTemplateEvidence.fromHistory('daily-brief', schedule, [
            incomplete,
          ]).hasManualResult,
          isFalse,
        );
      }
    },
  );
  test('idea results need no calendar source', () {
    final ideas = run(scheduleId: 'ideas');
    (ideas['result'] as Map)['sources'] = [];
    expect(
      AutomationTemplateEvidence.fromHistory(
        'idea-generator',
        {'id': 'ideas'},
        [ideas],
      ).hasManualResult,
      isTrue,
    );
  });
}
