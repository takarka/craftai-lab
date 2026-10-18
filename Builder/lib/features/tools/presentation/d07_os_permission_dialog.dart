import 'package:flutter/material.dart';

import '../../../ui_kit/controls.dart';
import '../../../ui_kit/identity.dart';
import '../../../ui_kit/tokens.dart';
import '../domain/tool_definition.dart';

/// D07 OS Permission Explanation Dialog (F14-04).
///
/// Explains why the tool needs device access before triggering the system OS prompt.
class D07OsPermissionDialog extends StatelessWidget {
  final ToolDefinition tool;
  final bool isDenied;
  final VoidCallback onProceedToSystem;
  final VoidCallback? onOpenSettings;

  const D07OsPermissionDialog({
    super.key,
    required this.tool,
    this.isDenied = false,
    required this.onProceedToSystem,
    this.onOpenSettings,
  });

  static Future<bool?> show(
    BuildContext context, {
    required ToolDefinition tool,
    bool isDenied = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => D07OsPermissionDialog(
        tool: tool,
        isDenied: isDenied,
        onProceedToSystem: () => Navigator.pop(ctx, true),
        onOpenSettings: () => Navigator.pop(ctx, false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(BuilderRadii.sheet)),
      ),
      padding: const EdgeInsets.all(BuilderSpace.lg),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: BuilderSpace.md),
                decoration: BoxDecoration(
                  color: BuilderColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(
              children: [
                const BuilderIcon(
                  BuilderGlyph.lock,
                  size: 24,
                  color: BuilderColors.primary,
                ),
                const SizedBox(width: BuilderSpace.xs),
                Expanded(
                  child: Text(
                    isDenied ? 'Разрешение отключено в системе' : 'Системный доступ: ${tool.displayName}',
                    style: BuilderTypography.titleMedium.copyWith(color: BuilderColors.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BuilderSpace.sm),

            Text(
              isDenied
                  ? 'Ранее доступ для инструмента «${tool.displayName}» был запрещён в настройках вашего телефона. '
                    'Чтобы ассистент мог обращаться к календарю или системным функциям, включите разрешение в настройках приложения.'
                  : 'Для работы инструмента «${tool.displayName}» ассистенту требуется доступ к системным службам телефона.\n\n'
                    '• Ассистент не читает SMS-сообщения, историю звонков и личную переписку.\n'
                    '• Любые изменения (создание уроков, звонки) требуют вашего подтверждения в чате.\n'
                    '• Вы можете отозвать разрешение в любой момент в настройках телефона.',
              style: BuilderTypography.bodyMedium.copyWith(
                color: BuilderColors.inkSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: BuilderSpace.lg),

            if (isDenied) ...[
              BuilderButton(
                key: const Key('d07.openSettingsBtn'),
                label: 'Открыть настройки устройства',
                variant: BuilderButtonVariant.primary,
                onPressed: () {
                  onOpenSettings?.call();
                },
              ),
              const SizedBox(height: BuilderSpace.xs),
              TextButton(
                key: const Key('d07.cancelBtn'),
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                ),
                child: Text(
                  'Отмена',
                  style: BuilderTypography.labelMedium.copyWith(color: BuilderColors.inkSecondary),
                ),
              ),
            ] else ...[
              BuilderButton(
                key: const Key('d07.proceedBtn'),
                label: 'Запросить системное разрешение',
                variant: BuilderButtonVariant.primary,
                onPressed: onProceedToSystem,
              ),
              const SizedBox(height: BuilderSpace.xs),
              TextButton(
                key: const Key('d07.cancelBtn'),
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                ),
                child: Text(
                  'Не сейчас',
                  style: BuilderTypography.labelMedium.copyWith(color: BuilderColors.inkSecondary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
