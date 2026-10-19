import 'dart:convert';
import 'dart:async';
import 'package:builder/app/providers.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:builder/features/schedules/infrastructure/builder_schedules_client.dart';
import 'package:builder/features/schedules/presentation/schedule_editor.dart';
import 'package:builder/features/schedules/presentation/schedules_page.dart';
import 'package:builder/features/session/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'poll completes a queued run and confirmed deletion removes its result',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var deleted = false;
      final run = <String, dynamic>{
        'id': 'r1',
        'scheduleId': 's1',
        'status': 'queued',
        'delivery': 'pending',
        'trigger': 'manual',
      };
      final client = BuilderSchedulesClient(
        CraftAiClient(
          baseUri: Uri.parse('https://example.test'),
          httpClient: MockClient((request) async {
            if (request.method == 'DELETE') {
              deleted = true;
              return http.Response('', 204);
            }
            final path = request.url.path;
            final Json body;
            if (path.endsWith('/schedules')) {
              body = {
                'items': [
                  {
                    'id': 's1',
                    'template': 'daily-brief',
                    'enabled': true,
                    'timeZone': 'Asia/Almaty',
                  },
                ],
              };
            } else if (path.endsWith('/runs')) {
              body = {
                'items': [run],
                'nextCursor': null,
              };
            } else {
              body = {
                ...run,
                'status': 'succeeded',
                'delivery': 'sent',
                'result': {
                  'sections': [
                    {
                      'title': 'Новый результат',
                      'items': ['Пункт'],
                    },
                  ],
                  'sources': [],
                  'gaps': [],
                },
              };
            }
            return http.Response(
              jsonEncode(body),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(
              (ref) => Stream.value(
                AuthenticatedSession(
                  ownerId: 'owner',
                  onboardingComplete: true,
                ),
              ),
            ),
            builderSchedulesClientProvider.overrideWithValue(client),
          ],
          child: const MaterialApp(home: SchedulesPage(ownerId: 'owner')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('История').first);
      await tester.tap(find.text('История').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('В очереди'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Новый результат'));
      expect(find.text('Новый результат'), findsOneWidget);
      await tester.ensureVisible(find.text('Удалить результат'));
      await tester.tap(find.text('Удалить результат'));
      await tester.pumpAndSettle();
      expect(deleted, isFalse);
      await tester.tap(find.text('Удалить').last);
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
      expect(find.text('Новый результат'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'editor restores saved context and blocks incomplete old responses',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> open(Json schedule) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionProvider.overrideWith(
                (ref) => Stream.value(
                  AuthenticatedSession(
                    ownerId: 'owner',
                    onboardingComplete: true,
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              home: ScheduleEditor(
                ownerId: 'owner',
                template: 'daily-brief',
                schedule: schedule,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await open({'extraContext': 'Сохранённый фрагмент'});
      expect(find.text('Сохранённый фрагмент'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await open({});
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );
  testWidgets('logout discards an in-flight response and hides owner data', (
    tester,
  ) async {
    final sessions = StreamController<SessionSnapshot>();
    addTearDown(sessions.close);
    final response = Completer<http.Response>();
    var calls = 0;
    final client = BuilderSchedulesClient(
      CraftAiClient(
        baseUri: Uri.parse('https://example.test'),
        httpClient: MockClient((r) {
          calls++;
          return response.future;
        }),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => sessions.stream),
          builderSchedulesClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(home: SchedulesPage(ownerId: 'owner')),
      ),
    );
    sessions.add(
      AuthenticatedSession(ownerId: 'owner', onboardingComplete: true),
    );
    await tester.pump();
    await tester.pump();
    expect(calls, 1);
    sessions.add(const SignedOut());
    await tester.pump();
    response.complete(
      http.Response(
        jsonEncode({
          'items': [
            {
              'id': 's1',
              'template': 'daily-brief',
              'enabled': true,
              'timeZone': 'PRIVATE ZONE',
            },
          ],
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('PRIVATE ZONE'), findsNothing);
    expect(find.text('Войдите в аккаунт'), findsOneWidget);
  });
  test(
    'schedule wire contract preserves version, cursor and run identity',
    () async {
      final requests = <http.Request>[];
      final client = BuilderSchedulesClient(
        CraftAiClient(
          baseUri: Uri.parse('https://example.test'),
          httpClient: MockClient((r) async {
            requests.add(r);
            return http.Response(
              jsonEncode(
                r.url.path.endsWith('/schedules')
                    ? {'items': []}
                    : r.url.path.endsWith('/runs')
                    ? {'items': [], 'nextCursor': null}
                    : {
                        'id': 'run-1',
                        'status': 'queued',
                        'delivery': 'pending',
                      },
              ),
              200,
            );
          }),
        ),
      );
      expect(await client.list(), isEmpty);
      await client.save('daily-brief', {'timeZone': 'Asia/Almaty'}, version: 7);
      expect(requests.last.headers['If-Match'], '"7"');
      expect(jsonDecode(requests.last.body)['timeZone'], 'Asia/Almaty');
      await client.save('idea-generator', {});
      expect(requests.last.headers.containsKey('If-Match'), isFalse);
      await client.pause('s1', paused: true);
      expect(requests.last.url.path, '/builder/schedules/s1/pause');
      await client.pause('s1', paused: false);
      expect(requests.last.url.path, '/builder/schedules/s1/resume');
      final run = await client.runNow('s1');
      expect(run['id'], 'run-1');
      await client.runs('s1', cursor: 'a+/=');
      expect(requests.last.url.queryParameters['cursor'], 'a+/=');
      await client.run('run-1');
      expect(requests.last.url.path, '/builder/runs/run-1');
      await client.deleteRun('run-1');
      expect(requests.last.method, 'DELETE');
      await client.registerDevice('installation', {
        'platform': 'android',
        'pushToken': 'token',
      });
      expect(requests.last.method, 'PUT');
      await client.revokeDevice('installation');
      expect(requests.last.url.path, '/builder/devices/installation');
      await client.delete('s1');
      expect(requests.last.method, 'DELETE');
    },
  );

  test('uncertain manual run is sent once and error propagates', () async {
    var calls = 0;
    final client = BuilderSchedulesClient(
      CraftAiClient(
        baseUri: Uri.parse('https://example.test'),
        httpClient: MockClient((r) async {
          calls++;
          throw http.ClientException('lost response');
        }),
      ),
    );
    await expectLater(
      client.runNow('s1'),
      throwsA(isA<CraftAiNetworkException>()),
    );
    expect(calls, 1);
  });

  testWidgets('editor requires consent and checks server grade limit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(
            (ref) => Stream.value(
              AuthenticatedSession(ownerId: 'owner', onboardingComplete: true),
            ),
          ),
        ],
        child: const MaterialApp(
          home: ScheduleEditor(ownerId: 'owner', template: 'idea-generator'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Сохранить');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byType(TextFormField).at(2), 'Математика');
    await tester.enterText(find.byType(TextFormField).at(3), '12');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    expect(find.text('Укажите класс 1–11'), findsOneWidget);
  });

  testWidgets(
    'failed run never displays an old result and delivery stays separate',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = BuilderSchedulesClient(
        CraftAiClient(
          baseUri: Uri.parse('https://example.test'),
          httpClient: MockClient(
            (r) async => http.Response(
              jsonEncode(
                r.url.path.endsWith('/schedules')
                    ? {
                        'items': [
                          {
                            'id': 's1',
                            'template': 'daily-brief',
                            'enabled': true,
                            'timeZone': 'Asia/Almaty',
                          },
                        ],
                      }
                    : {
                        'items': [
                          {
                            'id': 'r1',
                            'status': 'failed',
                            'statusReason': 'missing-input',
                            'delivery': 'not-registered',
                            'trigger': 'scheduled',
                            'scheduledForUtc': '2026-10-19T07:30:00Z',
                            'result': {
                              'sections': [
                                {'title': 'OLD RESULT', 'items': []},
                              ],
                              'sources': [],
                              'gaps': [],
                            },
                          },
                        ],
                        'nextCursor': null,
                      },
              ),
              200,
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(
              (ref) => Stream.value(
                AuthenticatedSession(
                  ownerId: 'owner',
                  onboardingComplete: true,
                ),
              ),
            ),
            builderSchedulesClientProvider.overrideWithValue(client),
          ],
          child: const MaterialApp(home: SchedulesPage(ownerId: 'owner')),
        ),
      );
      await tester.pumpAndSettle();
      // Session restoration may complete after the initial microtask.
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('История').first);
      await tester.tap(find.text('История').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Недостаточно исходных данных'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Устройство не зарегистрировано'),
        findsOneWidget,
      );
      expect(find.text('OLD RESULT'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
