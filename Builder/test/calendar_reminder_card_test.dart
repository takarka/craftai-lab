import 'package:builder/features/calendar/application/calendar_providers.dart';
import 'package:builder/features/calendar/domain/calendar_models.dart';
import 'package:builder/features/calendar/infrastructure/calendar_repository.dart';
import 'package:builder/features/calendar/infrastructure/reminder_scheduler.dart';
import 'package:builder/features/calendar/presentation/calendar_reminder_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_reminder_scheduler.dart';

String wall(DateTime utc) => utc.toIso8601String().substring(0, 19);

Future<InMemoryCalendarRepository> repoWithUpcomingLesson() async {
  final repo = InMemoryCalendarRepository();
  final start = DateTime.now().toUtc().add(const Duration(days: 2));
  await repo.applyChanges(
    'a',
    CalendarChangesPage(
      items: [
        CalendarChange(
          eventId: 'e1',
          event: CalendarEvent(
            id: 'e1',
            title: 'Урок',
            allDay: false,
            start: wall(start),
            end: wall(start.add(const Duration(minutes: 45))),
            timeZone: 'UTC',
            reminders: const [15],
            version: 1,
          ),
        ),
      ],
      nextCursor: 'c',
      hasMore: false,
    ),
    replaceAll: true,
  );
  return repo;
}

Future<void> pumpCard(
  WidgetTester tester, {
  required InMemoryCalendarRepository repo,
  required FakeScheduler scheduler,
  bool kk = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(repo),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        builderCalendarClientProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        home: Scaffold(body: CalendarReminderCard(ownerId: 'a', kk: kk)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

bool switchValue(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byKey(const Key('calendar.reminders.switch'))).value;

void main() {
  testWidgets('starts off and explains what a reminder is and is not', (tester) async {
    await pumpCard(tester, repo: await repoWithUpcomingLesson(), scheduler: FakeScheduler());
    expect(switchValue(tester), isFalse);
    expect(find.textContaining('Телефон не будет напоминать'), findsOneWidget);
    expect(find.textContaining('не запускает ассистента и не готовит Daily Brief'), findsOneWidget);
    expect(find.textContaining('Android может задержать'), findsOneWidget);
  });

  testWidgets('a refused permission leaves the switch off with the reason', (tester) async {
    final scheduler = FakeScheduler()
      ..current = ReminderPermission.denied
      ..onRequest = ReminderPermission.denied;
    await pumpCard(tester, repo: await repoWithUpcomingLesson(), scheduler: scheduler);

    await tester.tap(find.byKey(const Key('calendar.reminders.switch')));
    await tester.pump();
    await tester.pump();

    expect(switchValue(tester), isFalse);
    expect(find.textContaining('Разрешение на уведомления не выдано'), findsOneWidget);
    expect(scheduler.held, isEmpty);
  });

  testWidgets('allowing notifications schedules the upcoming reminder and shows the count', (tester) async {
    final scheduler = FakeScheduler();
    await pumpCard(tester, repo: await repoWithUpcomingLesson(), scheduler: scheduler);

    await tester.tap(find.byKey(const Key('calendar.reminders.switch')));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(switchValue(tester), isTrue);
    expect(find.textContaining('Запланировано: 1'), findsOneWidget);
    expect(scheduler.held, hasLength(1));

    await tester.tap(find.byKey(const Key('calendar.reminders.switch')));
    await tester.pump();
    await tester.pump();
    expect(switchValue(tester), isFalse);
    expect(scheduler.held, isEmpty);
  });

  testWidgets('with notifications blocked in the system the card says nothing will arrive', (tester) async {
    final repo = await repoWithUpcomingLesson();
    await repo.setRemindersEnabled('a', true);
    final scheduler = FakeScheduler()..current = ReminderPermission.denied;
    await pumpCard(tester, repo: repo, scheduler: scheduler);

    expect(find.textContaining('напоминания не придут'), findsOneWidget);
    expect(scheduler.held, isEmpty);
  });

  testWidgets('the Kazakh texts are shown for the Kazakh interface', (tester) async {
    await pumpCard(tester, repo: await repoWithUpcomingLesson(), scheduler: FakeScheduler(), kk: true);
    expect(find.text('Телефондағы еске салулар'), findsOneWidget);
    expect(find.textContaining('Daily Brief дайындамайды'), findsOneWidget);
  });
}
