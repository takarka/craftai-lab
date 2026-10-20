import 'package:flutter/material.dart';
import '../domain/course_models.dart';
import 'automation_practice_panel.dart';

/// Read-only C-03 material; does not submit quizzes or record practice evidence.
class AutomationLessonPreview extends StatelessWidget {
  const AutomationLessonPreview({
    super.key,
    required this.level,
    required this.ownerId,
  });
  final CourseLevel level;
  final String ownerId;

  @override
  Widget build(BuildContext context) {
    final kk = Localizations.localeOf(context).languageCode == 'kk';
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
    return Scaffold(
      appBar: AppBar(title: Text('${level.displayOrder}. ${level.title}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            kk
                ? 'Сабақты алдын ала оқу және тәжірибеге өту. Бағалау автоматтандыру іске қосылғаннан кейін қолжетімді болады. Бұл оқу үлгеріміне әсер етпейді.'
                : 'Предварительное чтение и переход к практике. Зачёт откроется после готовности автоматизации. Просмотр не меняет учебный прогресс.',
          ),
          heading(level.ideaTitle),
          Text(level.ideaText),
          const SizedBox(height: 12),
          Text(level.ideaExampleTemplate),
          heading(kk ? 'Тәжірибе жоспары' : 'План практики'),
          Text(level.practiceTask),
          AutomationPracticePanel(ownerId: ownerId),
          heading(kk ? 'Күтілетін нәтиже' : 'Ожидаемый результат'),
          Text(level.practiceExpectedAnswer),
          heading(kk ? 'Ішкі құрылымы' : 'Под капотом'),
          Text(level.underTheHoodConcept),
          Text(level.underTheHoodExplanation),
          for (final layer in level.underTheHoodLayers) ...[
            const SizedBox(height: 12),
            Text(
              layer['layer']!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(layer['detail']!),
          ],
          heading(kk ? 'Өзіңізді тексеріңіз' : 'Вопросы для самопроверки'),
          for (final question in level.quizQuestions) ...[
            Text(
              question.question,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (var i = 0; i < question.options.length; i++)
              Text('${i + 1}. ${question.options[i]}'),
            ExpansionTile(
              title: Text(
                kk ? 'Жауабы мен түсіндірмесі' : 'Ответ и объяснение',
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${question.options[question.correctIndex]}\n\n${question.explanation}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          heading(kk ? 'Қорытынды' : 'Итог'),
          Text(
            kk
                ? 'Енді еске салу мен AI кестесін ажырата аласыз, күнтізбе мен параметрлерді дайындау, іске қосу күйін және деректер уақытын тексеру, үзіліс пен жоюды қолдану жолын білесіз. Нақты жоспарлы нәтиже мен еске салудың тексерілуі әлі тәжірибеде расталуы керек.'
                : 'Теперь вы знаете, чем напоминание отличается от AI-расписания, как подготовить календарь и параметры, проверить статус запуска и время данных, поставить на паузу и удалить расписание. Получение настоящего планового результата и показ напоминания ещё предстоит подтвердить на практике.',
          ),
        ],
      ),
    );
  }
}
