import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'controls.dart';
import 'identity.dart';
import 'tokens.dart';

class BuilderCard extends StatelessWidget {
  const BuilderCard({
    super.key,
    required this.child,
    this.selected = false,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });
  final Widget child;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(BuilderRadii.card),
      boxShadow: BuilderShadows.card,
    ),
    child: Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BuilderRadii.card),
        side: selected
            ? const BorderSide(color: BuilderColors.primary, width: 1.5)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class BuilderIconTile extends StatelessWidget {
  const BuilderIconTile(
    this.icon, {
    super.key,
    this.warm = false,
    this.size = 44,
  });
  final BuilderGlyph icon;
  final bool warm;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: warm ? BuilderColors.warningTint : BuilderColors.primaryTint,
      borderRadius: BorderRadius.circular(BuilderRadii.tile),
    ),
    alignment: Alignment.center,
    child: BuilderIcon(
      icon,
      color: warm ? BuilderColors.warning : BuilderColors.primary,
    ),
  );
}

class BuilderNotice extends StatelessWidget {
  const BuilderNotice({
    super.key,
    required this.title,
    this.body,
    this.warning = false,
    this.action,
  });
  final String title;
  final String? body;
  final bool warning;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: warning ? BuilderColors.warningTint : BuilderColors.primaryTint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BuilderIcon(
          BuilderGlyph.info,
          color: warning ? BuilderColors.warning : BuilderColors.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: BuilderType.title.copyWith(
                  color: warning
                      ? BuilderColors.warning
                      : BuilderColors.primary,
                ),
              ),
              if (body != null) ...[const SizedBox(height: 6), Text(body!)],
              if (action != null) ...[const SizedBox(height: 10), action!],
            ],
          ),
        ),
      ],
    ),
  );
}

class BuilderEmptyState extends StatelessWidget {
  const BuilderEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.icon = BuilderGlyph.memory,
    this.action,
  });
  final String title;
  final String body;
  final BuilderGlyph icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      children: [
        BuilderIconTile(icon, size: 56),
        const SizedBox(height: 16),
        Text(title, style: BuilderType.h3, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: BuilderType.body.copyWith(color: BuilderColors.inkSecondary),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

enum LessonStatus { completed, current, locked, comingSoon }

class BuilderLessonCard extends StatelessWidget {
  const BuilderLessonCard({
    super.key,
    required this.level,
    required this.title,
    required this.description,
    required this.status,
    this.onPressed,
  });
  final int level;
  final String title;
  final String description;
  final LessonStatus status;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final current = status == LessonStatus.current;
    final locked =
        status == LessonStatus.locked || status == LessonStatus.comingSoon;
    final statusText = switch (status) {
      LessonStatus.completed => 'Пройден',
      LessonStatus.current => 'Текущий',
      LessonStatus.locked => 'Закрыто',
      LessonStatus.comingSoon => 'Скоро',
    };
    return BuilderCard(
      onTap: status == LessonStatus.completed ? onPressed : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: current
                      ? BuilderColors.warningTint
                      : locked
                      ? BuilderColors.surfaceDisabled
                      : BuilderColors.primaryTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: status == LessonStatus.completed
                    ? const BuilderIcon(
                        BuilderGlyph.check,
                        color: BuilderColors.primary,
                      )
                    : locked
                    ? const BuilderIcon(
                        BuilderGlyph.lock,
                        color: BuilderColors.inkSecondary,
                      )
                    : Text(
                        '$level',
                        style: BuilderType.h2.copyWith(
                          color: BuilderColors.warning,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('$level · $title', style: BuilderType.title),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(description, style: BuilderType.small),
          const SizedBox(height: 8),
          BuilderBadge(
            statusText,
            warning: current,
            neutral: locked,
            icon: status == LessonStatus.completed
                ? BuilderGlyph.check
                : locked
                ? BuilderGlyph.lock
                : null,
          ),
          if (current) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: BuilderButton(
                label: 'Продолжить',
                onPressed: onPressed,
                icon: BuilderGlyph.send,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum SkillStatus { enabled, disabled, locked, unavailable, comingSoon }

class BuilderSkillCard extends StatelessWidget {
  const BuilderSkillCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
    required this.level,
    this.location = DataLocation.device,
    this.onChanged,
    this.onTap,
  });
  final String title;
  final String subtitle;
  final BuilderGlyph icon;
  final SkillStatus status;
  final int level;
  final DataLocation location;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final available =
        status == SkillStatus.enabled || status == SkillStatus.disabled;
    final hint = switch (status) {
      SkillStatus.enabled => subtitle,
      SkillStatus.disabled => 'Выключено · $subtitle',
      SkillStatus.locked => 'Откроется после прохождения уровня $level',
      SkillStatus.unavailable => 'Недоступно в текущем режиме',
      SkillStatus.comingSoon => 'После MVP · скоро',
    };
    final cardContent = BuilderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BuilderIconTile(icon, warm: status == SkillStatus.enabled),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: BuilderType.title)),
              if (available)
                Switch(
                  value: status == SkillStatus.enabled,
                  onChanged: onChanged,
                  activeTrackColor: BuilderColors.primary,
                  activeThumbColor: Colors.white,
                )
              else
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: BuilderIcon(
                    BuilderGlyph.lock,
                    color: BuilderColors.inkSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(hint, style: BuilderType.small),
          if (available) BuilderDataChip(location, compact: true),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: cardContent,
      );
    }
    return cardContent;
  }
}

class BuilderModelCard extends StatelessWidget {
  const BuilderModelCard({
    super.key,
    required this.title,
    required this.description,
    required this.scores,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String description;
  final List<int> scores;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: BuilderCard(
      selected: selected,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuilderIconTile(BuilderGlyph.bolt),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: BuilderType.h3)),
              BuilderIcon(
                selected ? BuilderGlyph.check : BuilderGlyph.plus,
                color: BuilderColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(description),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      ['Качество', 'Скорость', 'Цена'][i],
                      style: BuilderType.small,
                    ),
                  ),
                  Expanded(child: BuilderProgress(completed: scores[i])),
                  const SizedBox(width: 8),
                  Text('${scores[i]}/5', style: BuilderType.mono),
                ],
              ),
            ),
          const BuilderDataChip(DataLocation.cloud, compact: true),
        ],
      ),
    ),
  );
}

class BuilderLinkRow extends StatelessWidget {
  const BuilderLinkRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final BuilderGlyph icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => BuilderCard(
    onTap: onTap,
    child: Row(
      children: [
        BuilderIconTile(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: BuilderType.title),
              const SizedBox(height: 4),
              Text(subtitle, style: BuilderType.small),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const BuilderIcon(
          BuilderGlyph.chevron,
          color: BuilderColors.inkSecondary,
        ),
      ],
    ),
  );
}

class BuilderAssistantHeader extends StatelessWidget {
  const BuilderAssistantHeader({
    super.key,
    required this.name,
    required this.subtitle,
    required this.onSettings,
  });
  final String name;
  final String subtitle;
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Semantics(
          button: true,
          label: 'Настройки ассистента',
          child: InkWell(
            onTap: onSettings,
            borderRadius: BorderRadius.circular(12),
            child: const BuilderCharacter(size: 48, compact: true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: BuilderType.title),
              const SizedBox(height: 4),
              Text('$subtitle · ИИ', style: BuilderType.small),
            ],
          ),
        ),
        BuilderIconButton(
          icon: BuilderGlyph.settings,
          label: 'Настройки ассистента',
          onPressed: onSettings,
        ),
      ],
    ),
  );
}

class BuilderBottomNavigation extends StatelessWidget {
  const BuilderBottomNavigation({
    super.key,
    required this.index,
    required this.onChanged,
  });
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Semantics(
                selected: index == i,
                button: true,
                child: InkWell(
                  onTap: () => onChanged(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BuilderIcon(
                          [
                            BuilderGlyph.robot,
                            BuilderGlyph.course,
                            BuilderGlyph.profile,
                          ][i],
                          color: index == i
                              ? BuilderColors.primary
                              : BuilderColors.inkSecondary,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ['Ассистент', 'Курс', 'Профиль'][i],
                          textAlign: TextAlign.center,
                          style: BuilderType.small.copyWith(
                            color: index == i
                                ? BuilderColors.primary
                                : BuilderColors.inkSecondary,
                            fontWeight: index == i
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

enum MessageState { ready, generating, error, stopped }

class BuilderMessage extends StatelessWidget {
  const BuilderMessage({
    super.key,
    required this.text,
    this.user = false,
    this.state = MessageState.ready,
    this.model = 'Рабочая',
    this.location = DataLocation.cloud,
    this.sources = const [],
    this.onInspect,
    this.onRetry,
    this.onStop,
  });
  final String text;
  final bool user;
  final MessageState state;
  final String model;
  final DataLocation location;
  final List<String> sources;
  final VoidCallback? onInspect;
  final VoidCallback? onRetry;
  final VoidCallback? onStop;
  @override
  Widget build(BuildContext context) => Align(
    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: EdgeInsets.only(left: user ? 24 : 0, right: user ? 0 : 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: user ? BuilderColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!user) ...[
            const Row(
              children: [
                BuilderCharacter(size: 32, compact: true),
                SizedBox(width: 8),
                Text('Ассистент · ИИ', style: BuilderType.title),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Text(
            text,
            style: BuilderType.body.copyWith(
              color: user ? Colors.white : BuilderColors.ink,
            ),
          ),
          if (!user) ...[
            const SizedBox(height: 8),
            Text('Модель: $model', style: BuilderType.small),
            BuilderDataChip(location, compact: true),
            if (sources.isNotEmpty)
              Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  title: Text(
                    'Источники · ${sources.length}',
                    style: BuilderType.small,
                  ),
                  children: [
                    for (final source in sources)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(source, style: BuilderType.small),
                      ),
                  ],
                ),
              ),
            if (state == MessageState.error)
              BuilderNotice(
                title: 'Не удалось получить ответ',
                warning: true,
                action: BuilderButton(
                  label: 'Повторить',
                  variant: BuilderButtonVariant.secondary,
                  onPressed: onRetry,
                ),
              )
            else if (state == MessageState.generating)
              Row(
                children: [
                  const Expanded(
                    child: Text('Ассистент думает…', style: BuilderType.small),
                  ),
                  BuilderButton(
                    label: 'Остановить',
                    variant: BuilderButtonVariant.text,
                    onPressed: onStop,
                  ),
                ],
              )
            else if (state == MessageState.stopped)
              const BuilderBadge('Остановлено вами', neutral: true)
            else
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  BuilderButton(
                    label: 'Под капотом',
                    icon: BuilderGlyph.code,
                    variant: BuilderButtonVariant.text,
                    onPressed: onInspect,
                  ),
                  BuilderIconButton(
                    icon: BuilderGlyph.doc,
                    label: 'Скопировать ответ',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ответ скопирован')),
                        );
                      }
                    },
                  ),
                ],
              ),
          ],
        ],
      ),
    ),
  );
}

class BuilderActionCard extends StatefulWidget {
  const BuilderActionCard({
    super.key,
    required this.title,
    required this.details,
    required this.onConfirm,
    this.onEdit,
  });
  final String title;
  final String details;
  final Future<void> Function() onConfirm;
  final VoidCallback? onEdit;
  @override
  State<BuilderActionCard> createState() => _BuilderActionCardState();
}

class _BuilderActionCardState extends State<BuilderActionCard> {
  String? _result;
  bool _busy = false;
  bool _error = false;
  Future<void> _confirm() async {
    if (_busy || _result != null) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      await widget.onConfirm();
      if (mounted) setState(() => _result = 'Выполнено');
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => BuilderCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BuilderBadge(
          'Подтвердите действие',
          icon: BuilderGlyph.calendar,
          warning: true,
        ),
        const SizedBox(height: 12),
        Text(widget.title, style: BuilderType.h3),
        const SizedBox(height: 8),
        Text(widget.details),
        const SizedBox(height: 12),
        if (_result != null)
          BuilderBadge(
            _result!,
            icon: _result == 'Выполнено'
                ? BuilderGlyph.check
                : BuilderGlyph.close,
            neutral: _result == 'Отменено',
          )
        else ...[
          const Text('Изменяет ваш календарь', style: BuilderType.small),
          if (_error) ...[
            const SizedBox(height: 8),
            const BuilderNotice(
              title: 'Действие не выполнено. Попробуйте ещё раз.',
              warning: true,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              BuilderButton(
                label: _busy ? 'Создаём…' : 'Подтвердить',
                loading: _busy,
                onPressed: _confirm,
              ),
              if (widget.onEdit != null)
                BuilderButton(
                  label: 'Изменить',
                  variant: BuilderButtonVariant.text,
                  onPressed: _busy ? null : widget.onEdit,
                ),
              BuilderButton(
                label: 'Отмена',
                variant: BuilderButtonVariant.secondary,
                onPressed: _busy
                    ? null
                    : () => setState(() => _result = 'Отменено'),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class BuilderSkeleton extends StatelessWidget {
  const BuilderSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Загрузка',
    child: BuilderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final width in [0.55, 1.0, 0.8])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FractionallySizedBox(
                widthFactor: width,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: BuilderColors.surfaceDisabled,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
