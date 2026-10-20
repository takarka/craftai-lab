import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/features/skills/domain/skill_preparation.dart';
import 'package:builder/features/skills/domain/skill_request.dart';
import 'package:builder/features/skills/domain/skill_scenario.dart';
import 'package:builder/features/skills/domain/skill_templates.dart';
import 'package:builder/features/trace/domain/request_trace.dart';
import 'package:builder/features/trace/presentation/trace_sheet.dart';
import 'package:builder/features/trace/trace_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SkillScenario _skill() => SkillScenario.fromJson({
  ...SkillTemplates.forLocale().first.toJson(),
  'revision': 2,
  'sources': ['Учебный текст во входах'],
});

String _prompt() => SkillPreparation.prepare(_skill(), {
  'Тема': 'Дроби',
  'Класс': '5',
}).userPrompt!;

RequestTrace _trace(String prompt) => RequestTrace.fromExecution(
  requestId: 'skill-trace',
  ownerId: 'alice',
  conversationId: 'chat',
  modelCategory: 'standard',
  assistantVersion: 3,
  userPrompt: prompt,
  responseText: 'Ответ',
  durationMs: 100,
  status: TraceStatus.completed,
  instructionTokens: 0,
  memoryTokens: 0,
);

void main() {
  test(
    'Trace reopens submitted scenario revision and inputs without new schema fields',
    () {
      final trace = RequestTrace.fromJson(_trace(_prompt()).toJson());
      expect(trace.skillRequest!.skill.revision, 2);
      expect(trace.skillRequest!.inputs, {'Тема': 'Дроби', 'Класс': '5'});
      expect(trace.skillRequest!.skill.sources, ['Учебный текст во входах']);
      expect(
        () => trace.skillRequest!.inputs['Тема'] = 'Другая',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'Legacy, malformed and incomplete requests do not become skill traces',
    () {
      for (final prompt in [
        'Обычный вопрос',
        '{}',
        '{"builder_skill_request":1}',
        '{"builder_skill_request":',
      ]) {
        expect(_trace(prompt).skillRequest, isNull);
        expect(SkillRequest.tryParse(prompt), isNull);
      }
      final valid = _trace(_prompt()).toJson();
      final layers = (valid['layers'] as List).cast<Map<String, dynamic>>();
      layers.firstWhere((l) => l['type'] == 'userPrompt')['type'] = 'history';
      expect(RequestTrace.fromJson(valid).skillRequest, isNull);
    },
  );

  for (final locale in ['ru', 'kk']) {
    testWidgets(
      'All three trace tabs show submitted skill context in $locale at 130%',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              traceProvider(
                'skill-trace',
              ).overrideWith((ref) async => _trace(_prompt())),
            ],
            child: MaterialApp(
              locale: Locale(locale),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: const Scaffold(body: TraceSheet(requestId: 'skill-trace')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final labels = locale == 'ru'
            ? ['Схема', 'Рентген', 'Аналогия']
            : ['Сұлба', 'Рентген', 'Ұқсастық'];
        for (final label in labels) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('trace.skillContext')), findsOneWidget);
          expect(find.text('Тема: Дроби'), findsOneWidget);
          expect(
            find.textContaining('Учебный текст во входах'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
