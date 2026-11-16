import 'package:flutter/material.dart';

/// PRD 0.2 §2 & LM06: 7-lesson configuration-driven Lab curriculum,
/// 6-step lesson player (объяснение → прогноз → одно изменение → реальный запуск → сравнение → задание),
/// server progress sync, and privacy-safe analytics without prompt/material text.
class LabCourseLessonConfig {
  final int id;
  final String title;
  final String explanation;
  final String predictionPrompt;
  final List<String> predictionOptions;
  final String changeTask;
  final String runPromptHint;
  final String comparisonQuestion;
  final String independentTask;
  final bool requiresMaterialId;
  final bool requiresSecondAgentWithoutWizard;

  const LabCourseLessonConfig({
    required this.id,
    required this.title,
    required this.explanation,
    required this.predictionPrompt,
    required this.predictionOptions,
    required this.changeTask,
    required this.runPromptHint,
    required this.comparisonQuestion,
    required this.independentTask,
    this.requiresMaterialId = false,
    this.requiresSecondAgentWithoutWizard = false,
  });
}

abstract final class LabCourseCatalog {
  static const String courseVersion = '0.2';

  static const List<LabCourseLessonConfig> lessons = [
    LabCourseLessonConfig(
      id: 1,
      title: '1. Инструкция и модель',
      explanation:
          'Модель отвечает за базовые возможности генерации, а инструкция агента задаёт роль, класс и формат ответа.',
      predictionPrompt:
          'Что изменится, если добавить в инструкцию правило «ровно 3 вопроса без ответов»?',
      predictionOptions: [
        'Агент выдаст ровно 3 вопроса без ответов',
        'Сменится языковая модель',
      ],
      changeTask:
          'Задайте инструкцию для 5 класса: «Готовь ровно три нумерованных вопроса. Не добавляй ответы».',
      runPromptHint: 'Подготовь вопросы по теме испарения',
      comparisonQuestion: 'Совпал ли формат ответа с вашим прогнозом?',
      independentTask:
          'Объясните отличие модели от правил в инструкции агента.',
    ),
    LabCourseLessonConfig(
      id: 2,
      title: '2. Контекст и фото',
      explanation:
          'Агент опирается только на переданный учебный фрагмент или проверенный текст с фото.',
      predictionPrompt:
          'Что произойдёт, если передать учебный фрагмент об испарении в контекст?',
      predictionOptions: [
        'Вопросы будут составлены строго по тексту фрагмента',
        'Фрагмент автоматически изменит системную инструкцию',
      ],
      changeTask:
          'Добавьте текстовый материал или проверьте распознанный текст с фото.',
      runPromptHint: 'Подготовь вопросы по добавленному материалу',
      comparisonQuestion: 'Какие сведения были переданы в текущий запрос?',
      independentTask:
          'Проверьте в «Как выполнено», какие фрагменты вошли в запрос.',
    ),
    LabCourseLessonConfig(
      id: 3,
      title: '3. Инструмент и MCP',
      explanation:
          'Управляемый MCP-сервер «Материалы» позволяет сохранять (`save_material`) и искать (`search_materials`) учебные фрагменты с подтверждением.',
      predictionPrompt:
          'Что требуется, чтобы агент сохранил материал через MCP?',
      predictionOptions: [
        'Включённое разрешение save_material и подтверждение пользователя',
        'Достаточно написать в чате «сохрани» без разрешений',
      ],
      changeTask: 'Включите инструмент save_material в настройках агента.',
      runPromptHint: 'Сохрани материал «Испарение»',
      comparisonQuestion:
          'Появился ли идентификатор сохранённого материала (material_id) в трассе?',
      independentTask:
          'Найдите сохранённый материал в новом диалоге через search_materials.',
      requiresMaterialId: true,
    ),
    LabCourseLessonConfig(
      id: 4,
      title: '4. Скилл',
      explanation:
          'Скилл — версионированный шаблон инструкций для конкретной задачи. Он не выдаёт разрешений на инструменты.',
      predictionPrompt:
          'Даст ли включение скилла «Подготовка заданий» доступ к отключённому инструменту?',
      predictionOptions: [
        'Нет, скилл меняет только структуру задания, но не доступы',
        'Да, скилл автоматически включает все инструменты',
      ],
      changeTask:
          'Включите скилл «Подготовка заданий» и уточните разрешённое правило (2 вопроса с краткими ответами).',
      runPromptHint: 'Составь проверочные вопросы по теме',
      comparisonQuestion:
          'Как изменилась структура ответа после включения скилла?',
      independentTask:
          'Отличите инструкцию скилла от разрешения на вызов инструмента.',
    ),
    LabCourseLessonConfig(
      id: 5,
      title: '5. Память и границы',
      explanation:
          'Долгосрочная память хранит подтверждённые факты об учебном классе и немедленно исключает их из нового контекста после удаления.',
      predictionPrompt:
          'Что произойдёт после удаления записи «5 класс» из памяти агента?',
      predictionOptions: [
        'В новых запросах запись больше не передаётся в контекст',
        'Удаление памяти сотрёт прошлые сообщения диалога',
      ],
      changeTask:
          'Сохраните предпочтение «пятый класс» в память, затем удалите его.',
      runPromptHint: 'Проверь контекст после удаления записи памяти',
      comparisonQuestion:
          'Осталась ли удалённая запись в контексте нового запуска?',
      independentTask:
          'Объясните разницу между историей чата, текущим контекстом и памятью.',
    ),
    LabCourseLessonConfig(
      id: 6,
      title: '6. Harness и проверка',
      explanation:
          'Среда выполнения (Harness) контролирует лимиты (3 вызова инструментов, 60 секунд, 15 минут на подтверждение) и фиксирует достоверную трассу.',
      predictionPrompt:
          'Что сделает среда выполнения при попытке 4-го вызова инструмента за один запуск?',
      predictionOptions: [
        'Остановит запуск со статусом превышения лимита инструментов',
        'Скрыто увеличит лимит без уведомления',
      ],
      changeTask:
          'Проверьте карточку подтверждения и лимиты выполнения в заголовке чата.',
      runPromptHint: 'Выполни запрос с проверкой трассы «Как выполнено»',
      comparisonQuestion:
          'Видны ли в «Как выполнено» версия конфигурации, вызовы и причина остановки?',
      independentTask:
          'Разберите цепочку: модель → запрос инструмента → подтверждение → результат.',
    ),
    LabCourseLessonConfig(
      id: 7,
      title: '7. Перенос навыка',
      explanation:
          'Итоговая проверка: самостоятельное создание второго агента для новой педагогической задачи на второй модели без пошагового мастера.',
      predictionPrompt:
          'Сохранится ли прогресс курса и первый агент при создании второго агента?',
      predictionOptions: [
        'Да, агенты изолированы, а прогресс курса хранится отдельно',
        'Нет, первый агент заменится вторым',
      ],
      changeTask:
          'Без пошагового мастера создайте второго агента на второй модели и задайте собственные правила.',
      runPromptHint: 'Объясни новую тему для выбранного класса',
      comparisonQuestion:
          'Работает ли второй агент независимо от первого и на второй модели?',
      independentTask:
          'Выполните собственную проверку второго агента и оцените результат по чек-листу.',
      requiresSecondAgentWithoutWizard: true,
    ),
  ];

  static LabCourseLessonConfig byId(int id) =>
      lessons.firstWhere((e) => e.id == id, orElse: () => lessons.first);
}

class LabRunCompletionEvidence {
  final String runId;
  final String status;
  final String? materialId;
  final bool createdSecondAgentWithoutWizard;
  final bool usedSecondModel;

  const LabRunCompletionEvidence({
    required this.runId,
    required this.status,
    this.materialId,
    this.createdSecondAgentWithoutWizard = false,
    this.usedSecondModel = false,
  });
}

class LabCourseProgressState {
  final String courseVersion;
  final int currentLesson;
  final List<int> completedLessons;

  const LabCourseProgressState({
    this.courseVersion = LabCourseCatalog.courseVersion,
    this.currentLesson = 1,
    this.completedLessons = const [],
  });

  LabCourseProgressState mergeUpgrade(String newVersion) {
    return LabCourseProgressState(
      courseVersion: newVersion,
      currentLesson: currentLesson,
      completedLessons: List<int>.unmodifiable(
        {...completedLessons}.toList()..sort(),
      ),
    );
  }

  LabCourseProgressState markCompleted(int lessonId) {
    final merged = {...completedLessons, lessonId}.toList()..sort();
    final nextLesson = lessonId < 7 ? lessonId + 1 : 7;
    return LabCourseProgressState(
      courseVersion: courseVersion,
      currentLesson: nextLesson > currentLesson ? nextLesson : currentLesson,
      completedLessons: List<int>.unmodifiable(merged),
    );
  }

  Map<String, dynamic> toJson() => {
    'course_version': courseVersion,
    'current_lesson': currentLesson,
    'completed_lessons': completedLessons,
  };

  factory LabCourseProgressState.fromJson(Map<String, dynamic> json) {
    final raw = (json['completed_lessons'] as List?) ?? const [];
    return LabCourseProgressState(
      courseVersion:
          (json['course_version'] as String?) ?? LabCourseCatalog.courseVersion,
      currentLesson: (json['current_lesson'] as int?) ?? 1,
      completedLessons: raw.whereType<int>().toList()..sort(),
    );
  }
}

/// PRD 0.2 §9: Product analytics stores statuses, durations, and counts ONLY.
/// Full prompt, instruction, or material texts are strictly stripped/forbidden.
class LabCourseAnalytics {
  final List<Map<String, Object>> events = [];

  static const Set<String> _forbiddenTextKeys = {
    'prompt',
    'text',
    'content',
    'instruction',
    'material_text',
    'extracted_text',
    'final_output',
  };

  void record(String eventName, Map<String, Object?> rawProperties) {
    final sanitized = <String, Object>{'event': eventName};
    for (final entry in rawProperties.entries) {
      if (_forbiddenTextKeys.contains(entry.key.toLowerCase())) {
        continue;
      }
      final val = entry.value;
      if (val is num) {
        sanitized[entry.key] = val;
      } else if (val is bool) {
        sanitized[entry.key] = val;
      } else if (val is String && val.length <= 64) {
        sanitized[entry.key] = val;
      }
    }
    events.add(Map.unmodifiable(sanitized));
  }
}

class LabLessonPlayerPage extends StatefulWidget {
  final LabCourseLessonConfig lesson;
  final LabCourseProgressState initialProgress;
  final LabCourseAnalytics? analytics;
  final Future<LabRunCompletionEvidence> Function() onExecutePracticeRun;
  final Future<void> Function(LabCourseProgressState updatedProgress)?
  onSaveProgress;

  const LabLessonPlayerPage({
    super.key,
    required this.lesson,
    required this.initialProgress,
    required this.onExecutePracticeRun,
    this.onSaveProgress,
    this.analytics,
  });

  @override
  State<LabLessonPlayerPage> createState() => _LabLessonPlayerPageState();
}

class _LabLessonPlayerPageState extends State<LabLessonPlayerPage> {
  int _stepIndex =
      0; // 0: explanation, 1: prediction, 2: change, 3: run, 4: comparison, 5: task
  int? _selectedPrediction;
  bool _changeConfirmed = false;
  LabRunCompletionEvidence? _evidence;
  bool _comparisonConfirmed = false;
  bool _taskConfirmed = false;
  String? _gateError;
  late LabCourseProgressState _progress;

  static const _stepTitles = [
    '1. Объяснение',
    '2. Прогноз',
    '3. Одно изменение',
    '4. Реальный запуск',
    '5. Сравнение с прогнозом',
    '6. Самостоятельное задание',
  ];

  @override
  void initState() {
    super.initState();
    _progress = widget.initialProgress;
    widget.analytics?.record('lesson_started', {
      'lesson_id': widget.lesson.id,
      'course_version': _progress.courseVersion,
    });
  }

  bool get _canCompleteRunStep {
    final ev = _evidence;
    if (ev == null || ev.status != 'completed') return false;
    if (widget.lesson.requiresMaterialId &&
        (ev.materialId == null || ev.materialId!.isEmpty)) {
      return false;
    }
    if (widget.lesson.requiresSecondAgentWithoutWizard &&
        (!ev.createdSecondAgentWithoutWizard || !ev.usedSecondModel)) {
      return false;
    }
    return true;
  }

  Future<void> _triggerRun() async {
    setState(() => _gateError = null);
    final ev = await widget.onExecutePracticeRun();
    if (!mounted) return;
    setState(() {
      _evidence = ev;
      if (widget.lesson.requiresMaterialId &&
          (ev.materialId == null || ev.materialId!.isEmpty)) {
        _gateError =
            'Для завершения практики урока 3 необходим реальный вызов save_material с возвратом ID материала.';
      } else if (widget.lesson.requiresSecondAgentWithoutWizard &&
          (!ev.createdSecondAgentWithoutWizard || !ev.usedSecondModel)) {
        _gateError =
            'Для завершения урока 7 создайте второго агента без пошагового мастера на второй модели.';
      }
    });
    widget.analytics?.record('run_completed', {
      'lesson_id': widget.lesson.id,
      'status': ev.status,
      'has_material_id': ev.materialId != null && ev.materialId!.isNotEmpty,
    });
  }

  Future<void> _finishLesson() async {
    final updated = _progress.markCompleted(widget.lesson.id);
    setState(() => _progress = updated);
    widget.analytics?.record('final_check_completed', {
      'lesson_id': widget.lesson.id,
      'completed_count': updated.completedLessons.length,
    });
    await widget.onSaveProgress?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    return Scaffold(
      appBar: AppBar(title: Text(lesson.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _stepTitles[_stepIndex],
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_stepIndex == 0) ...[
            Text(lesson.explanation),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => setState(() => _stepIndex = 1),
              child: const Text('К прогнозу'),
            ),
          ] else if (_stepIndex == 1) ...[
            Text(lesson.predictionPrompt),
            const SizedBox(height: 8),
            RadioGroup<int>(
              groupValue: _selectedPrediction,
              onChanged: (v) => setState(() => _selectedPrediction = v),
              child: Column(
                children: [
                  for (var i = 0; i < lesson.predictionOptions.length; i++)
                    RadioListTile<int>(
                      value: i,
                      title: Text(lesson.predictionOptions[i]),
                    ),
                ],
              ),
            ),
            FilledButton(
              onPressed: _selectedPrediction != null
                  ? () => setState(() => _stepIndex = 2)
                  : null,
              child: const Text('К изменению агента'),
            ),
          ] else if (_stepIndex == 2) ...[
            Text(lesson.changeTask),
            CheckboxListTile(
              value: _changeConfirmed,
              title: const Text('Изменение внесено в настройках агента'),
              onChanged: (v) {
                setState(() => _changeConfirmed = v ?? false);
                if (v == true) {
                  widget.analytics?.record('component_changed', {
                    'lesson_id': lesson.id,
                  });
                }
              },
            ),
            FilledButton(
              onPressed: _changeConfirmed
                  ? () => setState(() => _stepIndex = 3)
                  : null,
              child: const Text('Перейти к запуску'),
            ),
          ] else if (_stepIndex == 3) ...[
            Text('Запрос: ${lesson.runPromptHint}'),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('lab_lesson_execute_run'),
              onPressed: _triggerRun,
              child: const Text('Выполнить реальный запуск'),
            ),
            if (_gateError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _gateError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('lab_lesson_after_run_next'),
              onPressed: _canCompleteRunStep
                  ? () => setState(() => _stepIndex = 4)
                  : null,
              child: const Text('К сравнению с прогнозом'),
            ),
          ] else if (_stepIndex == 4) ...[
            Text(lesson.comparisonQuestion),
            CheckboxListTile(
              value: _comparisonConfirmed,
              title: const Text('Результат сравнён с прогнозом и трассой'),
              onChanged: (v) =>
                  setState(() => _comparisonConfirmed = v ?? false),
            ),
            FilledButton(
              onPressed: _comparisonConfirmed
                  ? () => setState(() => _stepIndex = 5)
                  : null,
              child: const Text('К самостоятельному заданию'),
            ),
          ] else if (_stepIndex == 5) ...[
            Text(lesson.independentTask),
            CheckboxListTile(
              value: _taskConfirmed,
              title: const Text('Самостоятельное задание выполнено'),
              onChanged: (v) => setState(() => _taskConfirmed = v ?? false),
            ),
            FilledButton(
              key: const Key('lab_lesson_complete_btn'),
              onPressed: _taskConfirmed ? _finishLesson : null,
              child: const Text('Завершить урок'),
            ),
            if (_progress.completedLessons.contains(lesson.id))
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Урок завершён и сохранён.'),
              ),
          ],
        ],
      ),
    );
  }
}
