import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ui_kit/ui_kit.dart';
import '../../instructions/instructions_providers.dart';
import '../../instructions/presentation/instructions_page.dart';
import '../../knowledge/presentation/knowledge_page.dart';
import '../../knowledge/presentation/knowledge_providers.dart';
import '../../memory/presentation/memory_page.dart';
import '../../memory/presentation/memory_providers.dart';
import '../../tools/presentation/tools_page.dart';
import '../../tools/presentation/tools_providers.dart';
import '../course_providers.dart';
import '../domain/course_catalog.dart';
import '../domain/course_models.dart';
import 'course_strings.dart';

class LessonPlayerPage extends ConsumerStatefulWidget {
  const LessonPlayerPage({
    super.key,
    required this.ownerId,
    required this.levelId,
    this.readOnly = false,
  });

  final String ownerId;
  final int levelId;
  final bool readOnly;

  @override
  ConsumerState<LessonPlayerPage> createState() => _LessonPlayerPageState();
}

class _LessonPlayerPageState extends ConsumerState<LessonPlayerPage> {
  LessonStep _currentStep = LessonStep.idea;
  bool _practiceEvidenceMet = false;
  bool _initialized = false;

  // S23 Practice interactive state
  bool _practiceApplied = false;
  bool _showComparison = false;
  final TextEditingController _practiceInputController =
      TextEditingController();

  // S25 Quiz state
  final Map<int, int> _selectedQuizAnswers = {};
  bool _quizSubmitted = false;
  bool _quizPassed = false;
  double _quizScore = 0.0;

  @override
  void initState() {
    super.initState();
    final level = CourseCatalog.getLevel(widget.levelId);
    if (level != null) {
      _practiceInputController.text = level.practiceDefaultInput;
    }
  }

  @override
  void dispose() {
    _practiceInputController.dispose();
    super.dispose();
  }

  void _initFromProgress(LevelProgress progress) {
    if (_initialized) return;
    _initialized = true;

    setState(() {
      if (progress.isCompleted) {
        _currentStep = LessonStep.idea;
      } else {
        _currentStep = LessonStep.fromNumber(progress.currentStep);
      }
      _practiceEvidenceMet = progress.practiceEvidenceMet;
    });
  }

  Future<void> _handleClose(BuildContext context) async {
    if (!widget.readOnly) {
      // Save checkpoint on close (F10-04, F10-12)
      await ref
          .read(courseControllerProvider(widget.ownerId))
          .saveStep(
            widget.levelId,
            _currentStep,
            practiceEvidenceMet: _practiceEvidenceMet,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: Key('course.progressSavedToast'),
            content: Text('Прогресс сохранён'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
    if (context.mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _moveToStep(LessonStep step) async {
    setState(() {
      _currentStep = step;
    });

    if (!widget.readOnly) {
      await ref
          .read(courseControllerProvider(widget.ownerId))
          .saveStep(
            widget.levelId,
            step,
            practiceEvidenceMet: _practiceEvidenceMet,
          );
    }
  }

  Future<void> _submitQuiz(CourseLevel level) async {
    final cs = CourseStrings.of(context);
    if (_selectedQuizAnswers.length < level.quizQuestions.length) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(cs.answerAllQuestions)));
      return;
    }

    final answers = List.generate(
      level.quizQuestions.length,
      (i) => _selectedQuizAnswers[i] ?? -1,
    );

    int correct = 0;
    for (int i = 0; i < level.quizQuestions.length; i++) {
      if (answers[i] == level.quizQuestions[i].correctIndex) {
        correct++;
      }
    }

    final score = correct / level.quizQuestions.length;
    final passed = score >= level.quizPassThreshold;

    setState(() {
      _quizSubmitted = true;
      _quizScore = score;
      _quizPassed = passed;
    });

    if (!widget.readOnly) {
      await ref
          .read(courseControllerProvider(widget.ownerId))
          .submitQuiz(
            widget.levelId,
            answers,
            threshold: level.quizPassThreshold,
          );
    }
  }

  Future<void> _completeLevelAndAdvance(BuildContext context) async {
    if (!widget.readOnly) {
      await ref
          .read(courseControllerProvider(widget.ownerId))
          .completeLevel(widget.levelId);
    }

    if (context.mounted) {
      if (widget.levelId < 5) {
        // Navigate to next level
        context.pushReplacement('/course/lesson/${widget.levelId + 1}');
      } else {
        // Course finished! Return to course page
        context.go('/course');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = CourseStrings.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final level =
        CourseCatalog.getLevel(widget.levelId, locale: locale) ??
        CourseCatalog.getLevel(widget.levelId);
    if (level == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(cs.t('Уровень не найден', 'Деңгей табылмады')),
        ),
      );
    }

    final progressAsync = ref.watch(
      levelProgressProvider((ownerId: widget.ownerId, levelId: widget.levelId)),
    );
    ref.listen(
      levelProgressProvider((ownerId: widget.ownerId, levelId: widget.levelId)),
      (prev, next) {
        next.whenData((p) {
          if (!_initialized && p != null) _initFromProgress(p);
        });
      },
    );
    progressAsync.whenData((p) {
      if (!_initialized && p != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_initialized) _initFromProgress(p);
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('lesson.closeBtn'),
          icon: const BuilderIcon(BuilderGlyph.close),
          onPressed: () => _handleClose(context),
        ),
        title: Text(
          '${cs.levelPrefix(level.id)} · ${level.title}',
          style: BuilderType.title,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _StepIndicator(
            currentStep: _currentStep,
            isKk: cs.kk,
            onStepTap: (step) {
              if (widget.readOnly ||
                  step.stepNumber <= _currentStep.stepNumber ||
                  _practiceEvidenceMet) {
                _moveToStep(step);
              }
            },
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildStepContent(level, cs),
              ),
            ),
            _buildBottomBar(level, cs),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(CourseLevel level, CourseStrings cs) {
    switch (_currentStep) {
      case LessonStep.idea:
        return _buildStepIdea(level, cs);
      case LessonStep.practice:
        return _buildStepPractice(level, cs);
      case LessonStep.underTheHood:
        return _buildStepUnderTheHood(level, cs);
      case LessonStep.quiz:
        return _buildStepQuiz(level, cs);
      case LessonStep.summary:
        return _buildStepSummary(level, cs);
    }
  }

  // --------------------------------------------------------------------------
  // S22: Идея
  // --------------------------------------------------------------------------
  Widget _buildStepIdea(CourseLevel level, CourseStrings cs) {
    return Column(
      key: const Key('lesson.step.1'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: BuilderColors.primaryTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            cs.stepIndicator(1, 5, LessonStep.idea),
            style: BuilderType.small.copyWith(
              color: BuilderColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(level.ideaTitle, style: BuilderType.h2),
        const SizedBox(height: 12),
        Text(
          level.ideaText,
          style: BuilderType.body.copyWith(fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 20),

        // Subject example card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: BuilderColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: BuilderColors.surfaceDisabled),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BuilderIcon(
                    BuilderGlyph.info,
                    size: 18,
                    color: BuilderColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cs.schoolExampleTitle,
                      style: BuilderType.title,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                level.ideaExampleTemplate,
                style: BuilderType.body.copyWith(
                  color: BuilderColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // S23: Практика
  // --------------------------------------------------------------------------
  Widget _buildStepPractice(CourseLevel level, CourseStrings cs) {
    return Column(
      key: const Key('lesson.step.2'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: BuilderColors.primaryTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            cs.stepIndicator(2, 5, LessonStep.practice),
            style: BuilderType.small.copyWith(
              color: BuilderColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(cs.practiceTitle, style: BuilderType.h2),
        const SizedBox(height: 8),
        Text(level.practiceTask, style: BuilderType.body),
        const SizedBox(height: 16),

        if (level.id == 2) ...[
          BuilderCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BuilderIcon(
                      BuilderGlyph.tool,
                      size: 20,
                      color: BuilderColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cs.t(
                          'Конструктор инструкций (S40)',
                          'Нұсқаулықтар құрастырғышы (S40)',
                        ),
                        style: BuilderType.title,
                      ),
                    ),
                    if (_practiceEvidenceMet)
                      BuilderBadge(
                        cs.practiceCompleted,
                        icon: BuilderGlyph.check,
                      )
                    else
                      BuilderBadge(cs.practiceRequired, neutral: true),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  cs.t(
                    'Откройте учебный экран S40: включите минимум 3 правила (роль, формат, ограничения), проверьте тестовый вопрос «До / после» и сохраните результат.',
                    'S40 оқу экранын ашыңыз: кемінде 3 ережені қосыңыз (рөл, пішім, шектеулер), «Дейін / кейін» тесттік сұрағын тексеріп, нәтижені сақтаңыз.',
                  ),
                  style: BuilderType.small,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: BuilderButton(
                    key: const Key('practice.openInstructionsSkillBtn'),
                    label: _practiceEvidenceMet
                        ? cs.t('Изменить инструкции', 'Нұсқаулықтарды өзгерту')
                        : cs.t(
                            'Открыть экран инструкций',
                            'Нұсқаулықтар экранын ашу',
                          ),
                    icon: BuilderGlyph.chevron,
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (ctx) => InstructionsPage(
                            ownerId: widget.ownerId,
                            mode: SkillScreenMode.learn,
                            onPracticeCompleted: () {
                              setState(() {
                                _practiceApplied = true;
                                _practiceEvidenceMet = true;
                                _showComparison = true;
                              });
                            },
                          ),
                        ),
                      );
                      final draft = ref.read(
                        instructionDraftProvider(widget.ownerId),
                      );
                      if (draft.config.enabledRulesCount >= 3 &&
                          draft.testResult != null) {
                        setState(() {
                          _practiceApplied = true;
                          _practiceEvidenceMet = true;
                          _showComparison = true;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (level.id == 3) ...[
          BuilderCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BuilderIcon(
                      BuilderGlyph.doc,
                      size: 20,
                      color: BuilderColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cs.t(
                          'База знаний и RAG (S41)',
                          'Білім қоры және RAG (S41)',
                        ),
                        style: BuilderType.title,
                      ),
                    ),
                    if (_practiceEvidenceMet)
                      BuilderBadge(
                        cs.practiceCompleted,
                        icon: BuilderGlyph.check,
                      )
                    else
                      BuilderBadge(cs.practiceRequired, neutral: true),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  cs.t(
                    'Откройте экран S41: загрузите документ, проверьте вопрос по документу (найдутся фрагменты) и вопрос не из документа (ассистент откажется выдумывать ответ).',
                    'S41 экранын ашыңыз: құжатты жүктеңіз, құжат бойынша сұрақты (үзінділер табылады) және құжаттан тыс сұрақты (ассистент ойдан шығарудан бас тартады) тексеріңіз.',
                  ),
                  style: BuilderType.small,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: BuilderButton(
                    key: const Key('practice.openKnowledgeSkillBtn'),
                    label: _practiceEvidenceMet
                        ? cs.t(
                            'Проверить знания снова',
                            'Білімді қайта тексеру',
                          )
                        : cs.t(
                            'Открыть экран базы знаний',
                            'Білім қоры экранын ашу',
                          ),
                    icon: BuilderGlyph.chevron,
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (ctx) => KnowledgePage(
                            ownerId: widget.ownerId,
                            isLearningMode: true,
                            onLearningCompleted: () {
                              setState(() {
                                _practiceApplied = true;
                                _practiceEvidenceMet = true;
                                _showComparison = true;
                              });
                            },
                          ),
                        ),
                      );
                      final kState = ref.read(
                        knowledgeControllerProvider(widget.ownerId),
                      );
                      if (kState.documents.isNotEmpty &&
                          kState.searchResult != null) {
                        setState(() {
                          _practiceApplied = true;
                          _practiceEvidenceMet = true;
                          _showComparison = true;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (level.id == 4) ...[
          BuilderCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BuilderIcon(
                      BuilderGlyph.memory,
                      size: 20,
                      color: BuilderColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cs.t(
                          'Долгая память и факты о классе (S42)',
                          'Ұзақ жады және сынып фактілері (S42)',
                        ),
                        style: BuilderType.title,
                      ),
                    ),
                    if (_practiceEvidenceMet)
                      BuilderBadge(
                        cs.practiceCompleted,
                        icon: BuilderGlyph.check,
                      )
                    else
                      BuilderBadge(cs.practiceRequired, neutral: true),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  cs.t(
                    'Откройте экран S42: сохраните неперсональные факты о классе (например: «В классе 24 ученика», «Урок 40 минут»), проверьте их использование и удалите факт.',
                    'S42 экранын ашыңыз: сынып туралы дербес емес фактілерді сақтаңыз (мысалы: «Сыныпта 24 оқушы бар», «Сабақ 40 минут»), олардың қолданылуын тексеріп, фактіні жойыңыз.',
                  ),
                  style: BuilderType.small,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: BuilderButton(
                    key: const Key('practice.openMemorySkillBtn'),
                    label: _practiceEvidenceMet
                        ? cs.t('Проверить память снова', 'Жадыны қайта тексеру')
                        : cs.t(
                            'Открыть экран долгой памяти',
                            'Ұзақ жады экранын ашу',
                          ),
                    icon: BuilderGlyph.chevron,
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (ctx) => MemoryPage(
                            ownerId: widget.ownerId,
                            isLearnMode: true,
                          ),
                        ),
                      );
                      final mState = ref.read(
                        memoryControllerProvider(widget.ownerId),
                      );
                      if (mState.facts.isNotEmpty) {
                        setState(() {
                          _practiceApplied = true;
                          _practiceEvidenceMet = true;
                          _showComparison = true;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (level.id == 5) ...[
          BuilderCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BuilderIcon(
                      BuilderGlyph.tool,
                      size: 20,
                      color: BuilderColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cs.t(
                          'Инструменты на устройстве (S43)',
                          'Құрылғыдағы құралдар (S43)',
                        ),
                        style: BuilderType.title,
                      ),
                    ),
                    if (_practiceEvidenceMet)
                      BuilderBadge(
                        cs.practiceCompleted,
                        icon: BuilderGlyph.check,
                      )
                    else
                      BuilderBadge(cs.practiceRequired, neutral: true),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  cs.t(
                    'Откройте экран S43: включите инструмент «Календарь уроков», проверьте разрешение и создайте тестовое событие расписания с обязательным подтверждением действия.',
                    'S43 экранын ашыңыз: «Сабақ кестесі күнтізбесі» құралын қосыңыз, рұқсатты тексеріп, әрекетті міндетті түрде растау арқылы кестенің тесттік оқиғасын жасаңыз.',
                  ),
                  style: BuilderType.small,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: BuilderButton(
                    key: const Key('practice.openToolsSkillBtn'),
                    label: _practiceEvidenceMet
                        ? cs.t(
                            'Проверить инструменты снова',
                            'Құралдарды қайта тексеру',
                          )
                        : cs.t(
                            'Открыть экран инструментов',
                            'Құралдар экранын ашу',
                          ),
                    icon: BuilderGlyph.chevron,
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (ctx) => ToolsPage(
                            ownerId: widget.ownerId,
                            isLearnMode: true,
                          ),
                        ),
                      );
                      final tRepo = ref.read(toolsRepositoryProvider);
                      final pending = await tRepo.getPendingActions(
                        widget.ownerId,
                      );
                      final grants = await tRepo.getGrants(widget.ownerId);
                      if (grants.any((g) => g.isEnabled) ||
                          pending.isNotEmpty) {
                        setState(() {
                          _practiceApplied = true;
                          _practiceEvidenceMet = true;
                          _showComparison = true;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Isolated Learning Draft
        BuilderCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BuilderIcon(
                    BuilderGlyph.bolt,
                    size: 18,
                    color: BuilderColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cs.practiceLearningDraft,
                      style: BuilderType.title,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_practiceEvidenceMet)
                    BuilderBadge(cs.practiceCompleted, icon: BuilderGlyph.check)
                  else
                    BuilderBadge(cs.practiceActiveTask, neutral: true),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('practice.inputField'),
                controller: _practiceInputController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: cs.practiceQueryField,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: BuilderButton(
                      key: const Key('practice.applyBtn'),
                      label: _practiceApplied
                          ? cs.practiceUpdateBtn
                          : cs.practiceApplyBtn,
                      onPressed: () {
                        setState(() {
                          _practiceApplied = true;
                          _practiceEvidenceMet =
                              true; // Evidence met on real interaction (F10-07)
                          _showComparison = true;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Before / After Comparison
        if (_showComparison) ...[
          const SizedBox(height: 16),
          Text(cs.comparisonTitle, style: BuilderType.title),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BuilderColors.surfaceDisabled,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cs.beforeSetting,
                  style: BuilderType.small.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(cs.beforePlaceholder, style: BuilderType.small),
                const Divider(height: 16),
                Text(
                  cs.afterSetting,
                  style: BuilderType.small.copyWith(
                    fontWeight: FontWeight.w700,
                    color: BuilderColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  level.practiceExpectedAnswer,
                  style: BuilderType.small.copyWith(color: BuilderColors.ink),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // --------------------------------------------------------------------------
  // S24: Под капотом
  // --------------------------------------------------------------------------
  Widget _buildStepUnderTheHood(CourseLevel level, CourseStrings cs) {
    return Column(
      key: const Key('lesson.step.3'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: BuilderColors.primaryTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            cs.stepIndicator(3, 5, LessonStep.underTheHood),
            style: BuilderType.small.copyWith(
              color: BuilderColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(level.underTheHoodConcept, style: BuilderType.h2),
        const SizedBox(height: 10),
        Text(level.underTheHoodExplanation, style: BuilderType.body),
        const SizedBox(height: 20),

        Text(cs.xrayLayersTitle, style: BuilderType.title),
        const SizedBox(height: 12),
        ...level.underTheHoodLayers.map(
          (layer) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BuilderColors.surfaceDisabled),
                boxShadow: BuilderShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BuilderIcon(
                        BuilderGlyph.code,
                        size: 16,
                        color: BuilderColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          layer['layer'] ?? '',
                          style: BuilderType.title,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    layer['detail'] ?? '',
                    style: BuilderType.small.copyWith(
                      color: BuilderColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // S25: Проверка
  // --------------------------------------------------------------------------
  Widget _buildStepQuiz(CourseLevel level, CourseStrings cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: BuilderColors.primaryTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            cs.stepIndicator(4, 5, LessonStep.quiz),
            style: BuilderType.small.copyWith(
              color: BuilderColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(cs.quizTitle, style: BuilderType.h2),
        const SizedBox(height: 6),
        Text(
          cs.quizSubtitle,
          style: BuilderType.body.copyWith(color: BuilderColors.inkSecondary),
        ),
        const SizedBox(height: 16),

        ...List.generate(level.quizQuestions.length, (qIndex) {
          final q = level.quizQuestions[qIndex];
          final selectedOption = _selectedQuizAnswers[qIndex];

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: BuilderCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${qIndex + 1}. ${q.question}',
                    style: BuilderType.title,
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(q.options.length, (optIndex) {
                    final opt = q.options[optIndex];
                    final isSelected = selectedOption == optIndex;
                    final isCorrect = optIndex == q.correctIndex;

                    Color tileColor = Colors.transparent;
                    if (_quizSubmitted) {
                      if (isCorrect) {
                        tileColor = BuilderColors.primaryTint;
                      } else if (isSelected) {
                        tileColor = BuilderColors.warningTint;
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: tileColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? BuilderColors.primary
                              : BuilderColors.surfaceDisabled,
                        ),
                      ),
                      // ignore: deprecated_member_use
                      child: RadioListTile<int>(
                        key: Key('quiz.q$qIndex.opt$optIndex'),
                        title: Text(opt, style: BuilderType.body),
                        value: optIndex,
                        // ignore: deprecated_member_use
                        groupValue: selectedOption,
                        // ignore: deprecated_member_use
                        onChanged: _quizSubmitted
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedQuizAnswers[qIndex] = val;
                                  });
                                }
                              },
                      ),
                    );
                  }),
                  if (_quizSubmitted) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: BuilderColors.surfaceDisabled,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${cs.explanationPrefix}${q.explanation}',
                        style: BuilderType.small.copyWith(
                          color: BuilderColors.ink,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),

        // Quiz Result Banner
        if (_quizSubmitted) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _quizPassed
                  ? BuilderColors.primaryTint
                  : BuilderColors.warningTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    BuilderIcon(
                      _quizPassed ? BuilderGlyph.check : BuilderGlyph.info,
                      color: _quizPassed
                          ? BuilderColors.primary
                          : BuilderColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _quizPassed ? cs.quizPassedTitle : cs.quizFailedTitle,
                        style: BuilderType.title.copyWith(
                          color: _quizPassed
                              ? BuilderColors.primary
                              : BuilderColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _quizPassed
                      ? cs.quizPassedScore((_quizScore * 100).toInt())
                      : cs.quizFailedScore((_quizScore * 100).toInt()),
                  style: BuilderType.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  // --------------------------------------------------------------------------
  // S26: Итог уровня
  // --------------------------------------------------------------------------
  Widget _buildStepSummary(CourseLevel level, CourseStrings cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: BuilderColors.primaryTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            cs.stepIndicator(5, 5, LessonStep.summary),
            style: BuilderType.small.copyWith(
              color: BuilderColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              const BuilderCharacter(size: 80, compact: false),
              const SizedBox(height: 16),
              Text(cs.levelCompletedTitle(level.id), style: BuilderType.h2),
              const SizedBox(height: 8),
              Text(
                cs.levelCompletedSubtitle,
                style: BuilderType.body.copyWith(
                  color: BuilderColors.inkSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        BuilderCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cs.whatChangedTitle, style: BuilderType.title),
              const SizedBox(height: 8),
              if (level.targetSkillName != null) ...[
                Row(
                  children: [
                    const BuilderIcon(
                      BuilderGlyph.check,
                      size: 16,
                      color: BuilderColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cs.unlockedSkill(level.targetSkillName!),
                        style: BuilderType.body,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  const BuilderIcon(
                    BuilderGlyph.check,
                    size: 16,
                    color: BuilderColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(cs.configSaved, style: BuilderType.body),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const BuilderIcon(
                    BuilderGlyph.check,
                    size: 16,
                    color: BuilderColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(cs.historySaved, style: BuilderType.body),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Bottom Navigation Bar
  // --------------------------------------------------------------------------
  Widget _buildBottomBar(CourseLevel level, CourseStrings cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: BuilderColors.surfaceDisabled)),
      ),
      child: Row(
        children: [
          if (_currentStep != LessonStep.idea) ...[
            BuilderButton(
              key: const Key('lesson.backBtn'),
              label: cs.previousStep,
              variant: BuilderButtonVariant.secondary,
              onPressed: () {
                final prevIndex = _currentStep.stepNumber - 1;
                if (prevIndex >= 1) {
                  _moveToStep(LessonStep.fromNumber(prevIndex));
                }
              },
            ),
            const SizedBox(width: 12),
          ],
          Expanded(child: _buildPrimaryAction(level, cs)),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction(CourseLevel level, CourseStrings cs) {
    switch (_currentStep) {
      case LessonStep.idea:
        return BuilderButton(
          key: const Key('lesson.ideaProceedBtn'),
          label: cs.tryIdeaBtn,
          onPressed: () => _moveToStep(LessonStep.practice),
        );

      case LessonStep.practice:
        return BuilderButton(
          key: const Key('lesson.practiceProceedBtn'),
          label: cs.nextUnderTheHoodBtn,
          onPressed: _practiceEvidenceMet || widget.readOnly
              ? () => _moveToStep(LessonStep.underTheHood)
              : null,
        );

      case LessonStep.underTheHood:
        return BuilderButton(
          key: const Key('lesson.underTheHoodProceedBtn'),
          label: cs.proceedToQuizBtn,
          onPressed: () => _moveToStep(LessonStep.quiz),
        );

      case LessonStep.quiz:
        if (!_quizSubmitted) {
          return BuilderButton(
            key: const Key('lesson.quizSubmitBtn'),
            label: cs.submitQuiz,
            onPressed: () => _submitQuiz(level),
          );
        }
        if (_quizPassed) {
          return BuilderButton(
            key: const Key('lesson.quizProceedBtn'),
            label: cs.proceedToSummaryBtn,
            onPressed: () => _moveToStep(LessonStep.summary),
          );
        }
        return BuilderButton(
          key: const Key('lesson.quizRetryBtn'),
          label: cs.retryQuiz,
          variant: BuilderButtonVariant.secondary,
          onPressed: () {
            setState(() {
              _quizSubmitted = false;
              _selectedQuizAnswers.clear();
            });
          },
        );

      case LessonStep.summary:
        return BuilderButton(
          key: const Key('lesson.summaryFinishBtn'),
          label: level.id < 5 ? cs.nextLevelBtn : cs.finishCourseBtn,
          onPressed: () => _completeLevelAndAdvance(context),
        );
    }
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.currentStep,
    required this.isKk,
    required this.onStepTap,
  });

  final LessonStep currentStep;
  final bool isKk;
  final ValueChanged<LessonStep> onStepTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BuilderSpace.md,
        0,
        BuilderSpace.md,
        BuilderSpace.xxs,
      ),
      child: Row(
        children: [
          for (final step in LessonStep.values) ...[
            if (step != LessonStep.values.first)
              const SizedBox(width: BuilderSpace.xxs),
            if (step == currentStep)
              Expanded(child: _buildStep(context, step))
            else
              SizedBox(width: 44, child: _buildStep(context, step)),
          ],
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context, LessonStep step) {
    final isCurrent = step == currentStep;
    final isPassed = step.stepNumber < currentStep.stepNumber;
    final color = isCurrent || isPassed
        ? BuilderColors.primary
        : BuilderColors.inkSecondary;
    final title = step.localizedTitle(isKk);

    return Semantics(
      label: isKk
          ? '${LessonStep.values.length} қадамның ${step.stepNumber}-қадамы: $title'
          : 'Шаг ${step.stepNumber} из ${LessonStep.values.length}: $title',
      selected: isCurrent,
      button: true,
      child: Tooltip(
        message: title,
        child: Material(
          color: isCurrent ? BuilderColors.primaryTint : Colors.transparent,
          borderRadius: BorderRadius.circular(BuilderRadii.control),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onStepTap(step),
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isCurrent ? BuilderSpace.xs : 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isPassed)
                      BuilderIcon(BuilderGlyph.check, size: 18, color: color)
                    else
                      Text(
                        '${step.stepNumber}',
                        style: BuilderType.small.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (isCurrent) ...[
                      const SizedBox(width: BuilderSpace.xs),
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BuilderType.small.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
