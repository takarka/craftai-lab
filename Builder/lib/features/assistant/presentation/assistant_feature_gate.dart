import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ui_kit/ui_kit.dart';
import '../assistant_providers.dart';
import '../domain/assistant_config.dart';

/// Gates normal navigation; lesson practice uses its own embedded editors.
class AssistantFeatureGate extends ConsumerWidget {
  const AssistantFeatureGate({
    super.key,
    required this.ownerId,
    required this.skill,
    required this.builder,
  });

  final String ownerId;
  final AssistantSkillId skill;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(completedCourseLevelsProvider(ownerId));
    final completed = progress.asData?.value;
    if (!progress.hasError &&
        completed != null &&
        completed.contains(skill.level) &&
        !skill.comingSoon) {
      return builder(context);
    }
    final isKk = Localizations.localeOf(context).languageCode == 'kk';
    return Scaffold(
      appBar: AppBar(
        title: Text(skill.title),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/assistant/settings');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (progress.isLoading && !progress.hasError)
                  const CircularProgressIndicator()
                else ...[
                  const Icon(
                    Icons.lock_outline,
                    size: 48,
                    color: BuilderColors.inkSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    progress.hasError
                        ? (isKk
                              ? 'Курс үлгерімі жүктелмеді'
                              : 'Не удалось загрузить прогресс курса')
                        : (isKk
                              ? '${skill.level}-деңгейді аяқтағаннан кейін ашылады'
                              : 'Откроется после прохождения уровня ${skill.level}'),
                    key: const Key('assistant.featureLocked'),
                    textAlign: TextAlign.center,
                    style: BuilderType.h3,
                  ),
                  const SizedBox(height: 12),
                  if (progress.hasError)
                    TextButton(
                      onPressed: () => ref.invalidate(
                        completedCourseLevelsProvider(ownerId),
                      ),
                      child: Text(isKk ? 'Қайталау' : 'Повторить'),
                    )
                  else
                    Text(
                      isKk
                          ? 'Алдымен курстағы тәжірибені орындаңыз.'
                          : 'Сначала выполните практику в курсе.',
                      textAlign: TextAlign.center,
                      style: BuilderType.body,
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go('/course'),
                    child: Text(isKk ? 'Курсқа өту' : 'Перейти к курсу'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
