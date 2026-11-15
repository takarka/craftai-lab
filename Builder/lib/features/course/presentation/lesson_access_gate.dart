import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../course_providers.dart';
import '../domain/course_catalog.dart';
import '../domain/course_models.dart';

/// Apply the same curriculum policy to direct links as to the course cards.
class LessonAccessGate extends ConsumerWidget {
  const LessonAccessGate({
    super.key,
    required this.ownerId,
    required this.levelId,
    required this.child,
  });
  final String ownerId;
  final int levelId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kk = Localizations.localeOf(context).languageCode == 'kk';
    final key = (ownerId: ownerId, levelId: levelId);
    return ref
        .watch(levelStatusProvider(key))
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => Scaffold(
            appBar: AppBar(),
            body: Center(
              child: TextButton(
                onPressed: () => ref.invalidate(levelStatusProvider(key)),
                child: Text(kk ? 'Қайта тексеру' : 'Повторить проверку'),
              ),
            ),
          ),
          data: (status) {
            if (status != LevelStatus.locked &&
                status != LevelStatus.comingSoon) {
              return child;
            }
            final level = CourseCatalog.getLevel(
              levelId,
              locale: kk ? 'kk' : 'ru',
            );
            return Scaffold(
              appBar: AppBar(title: Text(level?.title ?? '')),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    status == LevelStatus.locked
                        ? (kk
                              ? 'Алдымен алдыңғы деңгейді аяқтаңыз. Теорияны көруге болады.'
                              : 'Сначала завершите предыдущий уровень. Теорию можно прочитать ниже.')
                        : (kk ? 'Деңгей әзірленуде.' : 'Уровень готовится.'),
                  ),
                  if (status == LevelStatus.locked && level != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      level.ideaTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(level.ideaText),
                  ],
                ],
              ),
            );
          },
        );
  }
}
