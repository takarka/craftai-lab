import 'package:flutter/material.dart';
import 'identity.dart';
import 'tokens.dart';

enum BuilderButtonVariant { primary, secondary, danger, dangerFilled, text }

class BuilderButton extends StatelessWidget {
  const BuilderButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = BuilderButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.previewPressed = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final BuilderButtonVariant variant;
  final BuilderGlyph? icon;
  final bool loading;
  final String? loadingLabel;
  final bool previewPressed;

  @override
  Widget build(BuildContext context) {
    final filled =
        variant == BuilderButtonVariant.primary ||
        variant == BuilderButtonVariant.dangerFilled;
    final danger =
        variant == BuilderButtonVariant.danger ||
        variant == BuilderButtonVariant.dangerFilled;
    final base = danger ? BuilderColors.warning : BuilderColors.primary;
    final disabled = onPressed == null && !loading;
    final foreground = disabled
        ? BuilderColors.inkDisabled
        : filled
        ? Colors.white
        : base;
    return Semantics(
      label: loading ? loadingLabel ?? '$label, загрузка' : null,
      child: TextButton(
        onPressed: loading ? null : onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          foregroundColor: WidgetStatePropertyAll(foreground),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => disabled
                ? BuilderColors.surfaceDisabled
                : filled
                ? (previewPressed || states.contains(WidgetState.pressed)) &&
                          !danger
                      ? BuilderColors.primaryPressed
                      : base
                : variant == BuilderButtonVariant.text
                ? Colors.transparent
                : Colors.white,
          ),
          overlayColor: WidgetStatePropertyAll(base.withValues(alpha: 0.08)),
          side: WidgetStatePropertyAll(
            !filled && !disabled && variant != BuilderButtonVariant.text
                ? BorderSide(color: base, width: 1.5)
                : BorderSide.none,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BuilderRadii.control),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Onest',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                  value: MediaQuery.disableAnimationsOf(context) ? 0.7 : null,
                ),
              ),
              const SizedBox(width: 8),
            ] else if (icon != null) ...[
              BuilderIcon(icon!, size: 20, color: foreground),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}

class BuilderIconButton extends StatelessWidget {
  const BuilderIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.send = false,
  });
  final BuilderGlyph icon;
  final String label;
  final VoidCallback? onPressed;
  final bool send;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      minimumSize: const Size(44, 44),
      backgroundColor: send ? BuilderColors.primary : Colors.transparent,
      shape: send
          ? const CircleBorder()
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    icon: BuilderIcon(
      icon,
      color: onPressed == null
          ? BuilderColors.inkDisabled
          : send
          ? Colors.white
          : BuilderColors.primary,
    ),
  );
}

enum DataLocation {
  device(
    'На телефоне',
    BuilderGlyph.phone,
    'Эти данные хранятся и обрабатываются на вашем устройстве. Они не отправляются модели в облако.',
  ),
  cloud(
    'Облако · данные за рубежом',
    BuilderGlyph.globe,
    'Запрос передаётся через сервер CraftAI в OpenRouter и провайдеру модели. Не отправляйте имена учеников, оценки и другие персональные данные.',
  ),
  craft(
    'Сервис CraftAI',
    BuilderGlyph.cloud,
    'Демонстрационный сервер CraftAI предоставляет каталог уроков. Приложение отправляет ему только данные, необходимые для запроса.',
  ),
  kazakhstan(
    'Сервер в Казахстане',
    BuilderGlyph.cloud,
    'Зарезервированный режим. Сервер в Казахстане пока недоступен в MVP.',
  );

  const DataLocation(this.label, this.icon, this.explanation);
  final String label;
  final BuilderGlyph icon;
  final String explanation;
}

class BuilderBadge extends StatelessWidget {
  const BuilderBadge(
    this.label, {
    super.key,
    this.icon,
    this.warning = false,
    this.neutral = false,
  });
  final String label;
  final BuilderGlyph? icon;
  final bool warning;
  final bool neutral;
  @override
  Widget build(BuildContext context) {
    final color = warning
        ? BuilderColors.warning
        : neutral
        ? BuilderColors.inkSecondary
        : BuilderColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: warning
            ? BuilderColors.warningTint
            : neutral
            ? BuilderColors.background
            : BuilderColors.primaryTint,
        borderRadius: BorderRadius.circular(BuilderRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            BuilderIcon(icon!, size: 15, color: color),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: BuilderType.small.copyWith(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BuilderDataChip extends StatelessWidget {
  const BuilderDataChip(this.location, {super.key, this.compact = false});
  final DataLocation location;
  final bool compact;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Tooltip(
      message: 'Где обрабатываются данные',
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => showBuilderSheet(
          context,
          title: location.label,
          child: Text(location.explanation),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: BuilderBadge(
              compact && location == DataLocation.cloud
                  ? 'Данные за рубежом'
                  : location.label,
              icon: location.icon,
              warning: location == DataLocation.cloud,
              neutral: location == DataLocation.device,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<T?> showBuilderSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: BuilderType.h2)),
                BuilderIconButton(
                  icon: BuilderGlyph.close,
                  label: 'Закрыть',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    ),
  ),
);

class BuilderField extends StatelessWidget {
  const BuilderField({
    super.key,
    required this.label,
    this.hint,
    this.error,
    this.helper,
    this.initialValue,
    this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
    this.enabled = true,
  });
  final String label;
  final String? hint;
  final String? error;
  final String? helper;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: BuilderType.title),
      const SizedBox(height: 8),
      TextFormField(
        initialValue: initialValue,
        onChanged: onChanged,
        enabled: enabled,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: BuilderType.body,
        decoration: InputDecoration(
          hintText: hint,
          errorText: error,
          errorMaxLines: 4,
          helperText: helper,
          helperMaxLines: 3,
          semanticCounterText: label,
        ),
      ),
    ],
  );
}

class BuilderSegments<T> extends StatelessWidget {
  const BuilderSegments({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: BuilderColors.surfaceDisabled,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (key, label) in options)
          Expanded(
            child: Semantics(
              selected: key == value,
              button: true,
              child: Material(
                color: key == value ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onChanged(key),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: key == value
                            ? BuilderColors.primary
                            : BuilderColors.inkSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class BuilderProgress extends StatelessWidget {
  const BuilderProgress({
    super.key,
    required this.completed,
    this.total = 5,
    this.labels,
  });
  final int completed;
  final int total;
  final List<String>? labels;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Пройдено $completed из $total',
    child: Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < total; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < total - 1 ? 5 : 0),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: i < completed
                          ? BuilderColors.primary
                          : BuilderColors.lineDisabled,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (labels != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < total; i++)
                Expanded(
                  child: Text(
                    labels![i],
                    textAlign: TextAlign.center,
                    style: BuilderType.small.copyWith(
                      fontSize: 11,
                      color: i < completed
                          ? BuilderColors.primary
                          : BuilderColors.inkSecondary,
                      fontWeight: i == completed - 1
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

class BuilderToggleRow extends StatelessWidget {
  const BuilderToggleRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: BuilderType.title),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: BuilderType.small),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: BuilderColors.primary,
        ),
      ],
    ),
  );
}

class BuilderComposer extends StatefulWidget {
  const BuilderComposer({super.key, required this.onSend});
  final ValueChanged<String> onSend;
  @override
  State<BuilderComposer> createState() => _BuilderComposerState();
}

class _BuilderComposerState extends State<BuilderComposer> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    setState(_controller.clear);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    onChanged: (_) => setState(() {}),
    minLines: 1,
    maxLines: 4,
    style: BuilderType.body,
    decoration: InputDecoration(
      hintText: 'Напишите ассистенту…',
      suffixIcon: Padding(
        padding: const EdgeInsets.all(4),
        child: BuilderIconButton(
          icon: BuilderGlyph.send,
          label: 'Отправить сообщение',
          send: true,
          onPressed: _controller.text.trim().isEmpty ? null : _send,
        ),
      ),
    ),
  );
}
