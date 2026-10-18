import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ui_kit/ui_kit.dart';
import '../course_providers.dart';
import '../domain/course_catalog.dart';
import '../domain/course_models.dart';
import 'course_strings.dart';

class CoursePage extends ConsumerStatefulWidget {
  const CoursePage({super.key, required this.ownerId});

  final String ownerId;

  @override
  ConsumerState<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends ConsumerState<CoursePage> {
  void _handleOpenLevel(
    BuildContext context,
    CourseLevel level,
    LevelStatus status,
    LevelProgress? progress,
  ) {
    final cs = CourseStrings.of(context);
    if (status == LevelStatus.comingSoon) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cs.t(
              'Этот уровень будет доступен в следующем обновлении',
              'Бұл деңгей келесі жаңартуда қолжетімді болады',
            ),
          ),
        ),
      );
      return;
    }

    if (status == LevelStatus.locked) {
      // F10-13 / FR-LVL-03: Read-only preview of theory for locked levels
      _showLockedLevelPreview(context, level);
      return;
    }

    // Open lesson player S21
    context.push('/course/lesson/${level.id}');
  }

  void _showLockedLevelPreview(BuildContext context, CourseLevel level) {
    final cs = CourseStrings.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('course.theoryPreviewDialog'),
        title: Row(
          children: [
            const BuilderIcon(
              BuilderGlyph.lock,
              size: 20,
              color: BuilderColors.inkSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${cs.levelPrefix(level.id)} · ${cs.t('Превью теории', 'Теорияға шолу')}',
                style: BuilderType.title,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BuilderColors.primaryTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  cs.t(
                    'Откроется после прохождения Уровня ${level.id - 1}. Ниже доступна теория для ознакомления:',
                    '${level.id - 1}-деңгейді аяқтағаннан кейін ашылады. Төменде танысу үшін теория қолжетімді:',
                  ),
                  style: BuilderType.small.copyWith(
                    color: BuilderColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(level.ideaTitle, style: BuilderType.title),
              const SizedBox(height: 6),
              Text(level.ideaText, style: BuilderType.body),
              const SizedBox(height: 10),
              Text(
                level.ideaExampleTemplate,
                style: BuilderType.small.copyWith(
                  color: BuilderColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
        actions: [
          BuilderButton(
            label: cs.t('Понятно', 'Түсінікті'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = CourseStrings.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final levels = CourseCatalog.getLevels(locale: locale);
    final overallAsync = ref.watch(
      overallCourseProgressProvider(widget.ownerId),
    );
    final progressListAsync = ref.watch(
      courseProgressListProvider(widget.ownerId),
    );

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(courseProgressListProvider(widget.ownerId));
            ref.invalidate(overallCourseProgressProvider(widget.ownerId));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              // 1. Overall Progress Header (F10-02)
              overallAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (err, _) => const SizedBox.shrink(),
                data: (overall) => _CourseProgressHeader(
                  completedCount: overall.completedLevelsCount,
                  totalCount: overall.totalActiveLevels,
                  progressRatio: overall.progressRatio,
                  isAllCompleted: overall.isAllCompleted,
                  activeLevelId: overall.activeLevelId,
                  activeStep: overall.activeStep,
                  onResume: overall.activeLevelId != null
                      ? () => context.push(
                          '/course/lesson/${overall.activeLevelId}',
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),

              // 2. The MVP journey contains five active modules. Future
              // levels have a dedicated compact notice below the map.
              progressListAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, _) => Center(
                  child: Text(
                    '${cs.t('Ошибка загрузки курса', 'Курсты жүктеу қатесі')}: $err',
                  ),
                ),
                data: (progressList) {
                  return Column(
                    children: levels.where((lvl) => lvl.id <= 5).map((lvl) {
                      final p = progressList.firstWhere(
                        (item) => item.levelId == lvl.id,
                        orElse: () => LevelProgress(
                          ownerId: widget.ownerId,
                          levelId: lvl.id,
                          contentVersion: CourseCatalog.currentContentVersion,
                          currentStep: 1,
                          completedCheckpoints: const [],
                          attemptsCount: 0,
                          isCompleted: false,
                          updatedAtUtc: DateTime.now().toUtc(),
                        ),
                      );

                      // Calculate locked status if prev not completed
                      LevelStatus status = p.status;
                      if (lvl.id > 1 && lvl.id <= 5 && !p.isCompleted) {
                        final prev = progressList.firstWhere(
                          (item) => item.levelId == lvl.id - 1,
                          orElse: () => p,
                        );
                        if (!prev.isCompleted) {
                          status = LevelStatus.locked;
                        }
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _LevelCard(
                          key: Key('course.levelCard.${lvl.id}'),
                          level: lvl,
                          progress: p,
                          status: status,
                          onTap: () =>
                              _handleOpenLevel(context, lvl, status, p),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 4),

              // 3. Quick links
              Row(
                children: [
                  Expanded(
                    child: BuilderCard(
                      key: const Key('course.achievementsTile'),
                      padding: const EdgeInsets.all(12),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              cs.t(
                                'Достижения появятся после завершения MVP',
                                'Жетістіктер MVP аяқталған соң қолжетімді болады',
                              ),
                            ),
                          ),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BuilderIcon(
                            BuilderGlyph.robot,
                            size: 22,
                            color: BuilderColors.primary,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            cs.t('Достижения', 'Жетістіктер'),
                            style: BuilderType.title,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            cs.t('3 из 6', '6-дан 3'),
                            style: BuilderType.small.copyWith(
                              color: BuilderColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BuilderCard(
                      key: const Key('course.glossaryTile'),
                      padding: const EdgeInsets.all(12),
                      onTap: () => context.push('/course/glossary'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BuilderIcon(
                            BuilderGlyph.course,
                            size: 22,
                            color: BuilderColors.primary,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            cs.t('Словарь', 'Сөздік'),
                            style: BuilderType.title,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            cs.t('5 терминов', '5 термин'),
                            style: BuilderType.small.copyWith(
                              color: BuilderColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _ComingSoonNotice(cs: cs),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseProgressHeader extends StatelessWidget {
  const _CourseProgressHeader({
    required this.completedCount,
    required this.totalCount,
    required this.progressRatio,
    required this.isAllCompleted,
    this.activeLevelId,
    required this.activeStep,
    this.onResume,
  });

  final int completedCount;
  final int totalCount;
  final double progressRatio;
  final bool isAllCompleted;
  final int? activeLevelId;
  final LessonStep activeStep;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final cs = CourseStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BuilderColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: BuilderShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cs.courseTab, style: BuilderType.h2.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      cs.t('Соберите ассистента модуль за модулем', 'Ассистентті модуль-модульмен жинаңыз'),
                      style: BuilderType.small.copyWith(color: Colors.white.withValues(alpha: .88)),
                    ),
                  ],
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const BuilderIcon(
                  BuilderGlyph.robot, size: 30, color: BuilderColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(5, (index) {
              final current = !isAllCompleted && activeLevelId == index + 1;
              return Expanded(child: Container(
                height: 7,
                margin: EdgeInsets.only(right: index == 4 ? 0 : 5),
                decoration: BoxDecoration(
                  color: index < completedCount ? Colors.white : current ? BuilderColors.accent : Colors.white.withValues(alpha: .42),
                  borderRadius: BorderRadius.circular(8),
                ),
              ));
            }),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(cs.t('Уровень ${activeLevelId ?? 1} из 5', '5 деңгейдің ${activeLevelId ?? 1}-деңгейі'), style: BuilderType.small.copyWith(color: Colors.white)),
              Text(cs.t('пройдено $completedCount', '$completedCount аяқталды'), style: BuilderType.small.copyWith(color: Colors.white)),
            ],
          ),
          if (activeLevelId != null && !isAllCompleted && onResume != null) ...[
            const SizedBox(height: 10),
            InkWell(
              key: const Key('course.resumeBtn'),
              onTap: onResume,
              child: Text('${cs.levelPrefix(activeLevelId!)} · ${activeStep.localizedTitle(cs.kk)}', style: BuilderType.small.copyWith(color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    super.key,
    required this.level,
    required this.progress,
    required this.status,
    required this.onTap,
  });

  final CourseLevel level;
  final LevelProgress progress;
  final LevelStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = CourseStrings.of(context);
    Color cardBorderColor = Colors.transparent;
    if (status == LevelStatus.inProgress) {
      cardBorderColor = BuilderColors.accent;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: cardBorderColor,
          width: status == LevelStatus.inProgress ? 1.5 : 0.5,
        ),
        boxShadow: status == LevelStatus.locked ? null : BuilderShadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _statusBgColor(status),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        cs.levelPrefix(level.id),
                        style: BuilderType.small.copyWith(
                          color: _statusTextColor(status),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: _StatusBadge(
                            status: status,
                            step: progress.currentStep,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      cs.minutesSuffix(level.estimatedMinutes),
                      style: BuilderType.small.copyWith(
                        color: BuilderColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(level.title, style: BuilderType.h3),
                const SizedBox(height: 4),
                Text(
                  level.subtitle,
                  style: BuilderType.body.copyWith(
                    color: BuilderColors.inkSecondary,
                  ),
                ),
                if (level.targetSkillName != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const BuilderIcon(
                        BuilderGlyph.bolt,
                        size: 14,
                        color: BuilderColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${cs.t('Награда: ', 'Сыйлық: ')}${level.targetSkillName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BuilderType.small.copyWith(
                            color: BuilderColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _statusBgColor(LevelStatus status) {
    switch (status) {
      case LevelStatus.completed:
        return BuilderColors.primaryTint;
      case LevelStatus.inProgress:
        return BuilderColors.primary;
      case LevelStatus.available:
        return BuilderColors.surfaceDisabled;
      case LevelStatus.locked:
      case LevelStatus.comingSoon:
        return BuilderColors.surfaceDisabled;
    }
  }

  Color _statusTextColor(LevelStatus status) {
    switch (status) {
      case LevelStatus.completed:
        return BuilderColors.primary;
      case LevelStatus.inProgress:
        return Colors.white;
      case LevelStatus.available:
      case LevelStatus.locked:
      case LevelStatus.comingSoon:
        return BuilderColors.ink;
    }
  }
}

class _ComingSoonNotice extends StatelessWidget {
  const _ComingSoonNotice({required this.cs});
  final CourseStrings cs;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: BuilderColors.line, style: BorderStyle.solid),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      cs.t(
        'После MVP: голос, зрение, безопасность, агент (уровни 6–9) и сравнение моделей.',
        'MVP-ден кейін: дауыс, көру, қауіпсіздік, агент (6–9 деңгейлер) және модельдерді салыстыру.',
      ),
      style: BuilderType.small,
    ),
  );
}


class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.step});

  final LevelStatus status;
  final int step;

  @override
  Widget build(BuildContext context) {
    final cs = CourseStrings.of(context);
    switch (status) {
      case LevelStatus.completed:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: BuilderColors.primaryTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BuilderIcon(
                BuilderGlyph.check,
                size: 14,
                color: BuilderColors.primary,
              ),
              const SizedBox(width: 4),
              Text(
                cs.completed,
                style: BuilderType.small.copyWith(
                  color: BuilderColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      case LevelStatus.inProgress:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: BuilderColors.warningTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            cs.t('Шаг $step из 5', '5 қадамның $step-қадамы'),
            style: BuilderType.small.copyWith(
              color: BuilderColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case LevelStatus.available:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: BuilderColors.surfaceDisabled,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            cs.available,
            style: BuilderType.small.copyWith(
              color: BuilderColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case LevelStatus.locked:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: BuilderColors.surfaceDisabled,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BuilderIcon(
                BuilderGlyph.lock,
                size: 14,
                color: BuilderColors.inkSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  cs.locked,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BuilderType.small.copyWith(
                    color: BuilderColors.inkSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      case LevelStatus.comingSoon:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: BuilderColors.surfaceDisabled,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            cs.t('После MVP · скоро', 'MVP-ден кейін · жуықта'),
            style: BuilderType.small.copyWith(
              color: BuilderColors.inkSecondary,
            ),
          ),
        );
    }
  }
}
