import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../ui_kit/ui_kit.dart';
import '../../assistant/presentation/reset_confirmation_dialog.dart';
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
    final s = AppLocalizations.of(context);
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
      appBar: AppBar(
        title: Text(s.courseTab, style: BuilderType.h3),
        actions: [
          PopupMenuButton<String>(
            key: const Key('course.menuBtn'),
            icon: const BuilderIcon(BuilderGlyph.settings, size: 20),
            onSelected: (val) {
              if (val == 'reset') {
                showResetConfirmationDialog(context, ownerId: widget.ownerId);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    const BuilderIcon(
                      BuilderGlyph.reset,
                      size: 18,
                      color: BuilderColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      cs.resetCourseProgress,
                      style: const TextStyle(color: BuilderColors.warning),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(courseProgressListProvider(widget.ownerId));
            ref.invalidate(overallCourseProgressProvider(widget.ownerId));
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
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
              const SizedBox(height: 20),

              // 2. Section Title
              Text(cs.t('Учебный путь', 'Оқу жолы'), style: BuilderType.h3),
              const SizedBox(height: 12),

              // 3. 9 Levels List (F10-02, F10-V01)
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
                    children: levels.map((lvl) {
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

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // 4. Tiles: Glossary (S27) & Achievements (S53)
              Row(
                children: [
                  Expanded(
                    child: BuilderCard(
                      key: const Key('course.glossaryTile'),
                      onTap: () => context.push('/course/glossary'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BuilderIcon(
                            BuilderGlyph.doc,
                            size: 24,
                            color: BuilderColors.primary,
                          ),
                          const SizedBox(height: 8),
                          Text('Словарь ИИ', style: BuilderType.title),
                          const SizedBox(height: 4),
                          Text(
                            'Термины и понятия',
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
                      key: const Key('course.achievementsTile'),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Достижения будут доступны после завершения MVP',
                            ),
                          ),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BuilderIcon(
                            BuilderGlyph.robot,
                            size: 24,
                            color: BuilderColors.inkSecondary,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('Награды', style: BuilderType.title),
                              Text(
                                'Скоро',
                                style: BuilderType.small.copyWith(
                                  color: BuilderColors.inkDisabled,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Бейджи за уровни',
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
              const SizedBox(height: 32),
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
    return BuilderCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAllCompleted
                          ? cs.t(
                              'Курс успешно завершён!',
                              'Курс сәтті аяқталды!',
                            )
                          : cs.t('Прогресс курса', 'Курс прогресі'),
                      style: BuilderType.title,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cs.levelsCompleted(completedCount, totalCount),
                      style: BuilderType.body.copyWith(
                        color: BuilderColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isAllCompleted
                      ? BuilderColors.primaryTint
                      : BuilderColors.surfaceDisabled,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${(progressRatio * 100).toInt()}%',
                  style: BuilderType.title.copyWith(
                    color: isAllCompleted
                        ? BuilderColors.primary
                        : BuilderColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressRatio,
              minHeight: 8,
              backgroundColor: BuilderColors.surfaceDisabled,
              valueColor: const AlwaysStoppedAnimation<Color>(
                BuilderColors.primary,
              ),
            ),
          ),
          if (activeLevelId != null && !isAllCompleted && onResume != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cs.t('Текущий шаг', 'Ағымдағы қадам'),
                        style: BuilderType.small.copyWith(
                          color: BuilderColors.inkSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${cs.levelPrefix(activeLevelId!)} · ${activeStep.localizedTitle(cs.kk)}',
                        style: BuilderType.title,
                      ),
                    ],
                  ),
                ),
                BuilderButton(
                  key: const Key('course.resumeBtn'),
                  label: cs.t('Продолжить', 'Жалғастыру'),
                  onPressed: onResume,
                ),
              ],
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
      cardBorderColor = BuilderColors.primary;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cardBorderColor,
          width: status == LevelStatus.inProgress ? 1.5 : 0.5,
        ),
        boxShadow: BuilderShadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
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
