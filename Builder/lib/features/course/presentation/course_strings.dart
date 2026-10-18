import 'package:flutter/widgets.dart';
import '../domain/course_models.dart';

class CourseStrings {
  const CourseStrings.withLocale({bool isKk = false}) : kk = isKk;
  CourseStrings.of(BuildContext context)
    : kk = Localizations.localeOf(context).languageCode == 'kk';

  final bool kk;
  String t(String ru, String kz) => kk ? kz : ru;

  // Tabs and headers
  String get courseTab => t('Курс', 'Курс');
  String get resetCourseProgress =>
      t('Сбросить прогресс курса', 'Курс прогресін тазалау');
  String get resetCourseConfirmTitle =>
      t('Сбросить прогресс курса?', 'Курс прогресін тазалау керек пе?');
  String get resetCourseConfirmBody => t(
    'Весь прогресс прохождения уроков и зачётов будет обнулён. Настройки ассистента останутся без изменений.',
    'Барлық сабақтар мен сынақтардың өту прогресі нөлденеді. Ассистент баптаулары өзгеріссіз қалады.',
  );
  String get resetCourseConfirmBtn =>
      t('Сбросить прогресс', 'Прогресті тазалау');
  String get cancel => t('Отмена', 'Бас тарту');

  // Course overview page
  String get levelsProgressTitle =>
      t('Пять уровней мастерства', 'Шеберліктің бес деңгейі');
  String levelsCompleted(int completed, int total) => t(
    'Пройдено $completed из $total уровней',
    '$total деңгейдің $completed деңгейі аяқталды',
  );
  String levelPrefix(int id) => t('Уровень $id', '$id-деңгей');
  String get comingSoon => t('Скоро', 'Жуықта');
  String get completed => t('Пройден', 'Аяқталды');
  String get inProgress => t('В процессе', 'Орындалуда');
  String get available => t('Доступен', 'Қолжетімді');
  String get locked => t('Заблокирован', 'Бұғатталған');
  String minutesSuffix(int min) => t('$min мин', '$min мин');

  // Lesson player steps
  String stepIndicator(int step, int total, LessonStep lessonStep) {
    final name = switch (lessonStep) {
      LessonStep.idea => t('Идея', 'Идея'),
      LessonStep.practice => t('Практика', 'Тәжірибе'),
      LessonStep.underTheHood => t('Под капотом', 'Ішкі құрылымы'),
      LessonStep.quiz => t('Проверка', 'Тексеру'),
      LessonStep.summary => t('Итог', 'Қорытынды'),
    };
    return t(
      'Шаг $step из $total · $name',
      '$total қадамның $step-қадамы · $name',
    );
  }

  String get schoolExampleTitle =>
      t('Пример из школьной практики', 'Мектеп тәжірибесінен мысал');
  String get practiceTitle => t('Практическое задание', 'Тәжірибелік тапсырма');
  String get practiceCompleted => t('Выполнено', 'Орындалды');
  String get practiceRequired => t('Требуется действие', 'Әрекет қажет');
  String get practiceLearningDraft => t('Учебный черновик', 'Оқу шимайжазбасы');
  String get practiceActiveTask => t('Задание активно', 'Тапсырма белсенді');
  String get practiceQueryField =>
      t('Текст тестового запроса', 'Тесттік сұраныс мәтіні');
  String get practiceApplyBtn => t('Выполнить действие', 'Әрекетті орындау');
  String get practiceUpdateBtn => t('Обновить тест', 'Тестті жаңарту');

  String get comparisonTitle =>
      t('Сравнение до и после', 'Дейін және кейін салыстыру');
  String get beforeSetting => t('До настройки:', 'Баптауға дейін:');
  String get beforePlaceholder => t(
    '«Общий ответ без учёта правил и формата вашего предмета...»',
    '«Пәніңіздің ережелері мен пішімі ескерілмеген жалпы жауап...»',
  );
  String get afterSetting => t('После настройки:', 'Баптаудан кейін:');

  String get xrayLayersTitle =>
      t('Слои запроса (Рентген)', 'Сұраныс қабаттары (Рентген)');
  String get quizTitle =>
      t('Проверьте своё понимание', 'Түсінігіңізді тексеріңіз');
  String get quizSubtitle => t(
    'Ответьте на вопросы по теме уровня. Для зачёта требуется не менее 66% правильных ответов.',
    'Деңгей тақырыбы бойынша сұрақтарға жауап беріңіз. Сынақ үшін кемінде 66% дұрыс жауап қажет.',
  );
  String get quizPassedTitle => t('Зачёт сдан!', 'Сынақ тапсырылды!');
  String get quizFailedTitle =>
      t('Порог зачёта не пройден', 'Сынақ шегінен өтпедіңіз');
  String quizPassedScore(int scorePercent) => t(
    'Вы ответили верно на $scorePercent% вопросов. Переходите к итогу уровня!',
    'Сіз сұрақтардың $scorePercent%-на дұрыс жауап бердіңіз. Деңгей қорытындысына өтіңіз!',
  );
  String quizFailedScore(int scorePercent) => t(
    'Правильных ответов: $scorePercent%. Попробуйте ещё раз, чтобы закрепить материал.',
    'Дұрыс жауаптар: $scorePercent%. Материалды бекіту үшін қайталап көріңіз.',
  );
  String get explanationPrefix => t('Объяснение: ', 'Түсіндірме: ');

  String get answerAllQuestions => t(
    'Пожалуйста, ответьте на все вопросы',
    'Барлық сұрақтарға жауап беріңіз',
  );
  String quizProgress(int answered, int total) => t(
    'Отвечено: $answered из $total',
    'Жауап берілді: $total сұрақтың $answered-і',
  );
  String quizQuestionHeader(int current, int total) => t(
    'Вопрос $current из $total',
    '$total сұрақтың $current-сұрағы',
  );
  String get quizAnsweredBadge => t('Отвечено', 'Жауап берілді');
  String get quizPendingBadge => t('Ожидает ответа', 'Жауап күтілуде');
  String get quizAllAnswered =>
      t('Все ответы выбраны', 'Барлық жауаптар таңдалды');
  String quizAnswerSpecific(int num) => t(
    'Пожалуйста, ответьте на вопрос $num',
    '$num-сұраққа жауап беріңіз',
  );
  String quizSubmitWithCount(int answered, int total) => t(
    'Проверить ответы ($answered из $total)',
    'Жауаптарды тексеру ($answered/$total)',
  );
  String get quizNextQuestion => t('К следующему вопросу ↓', 'Келесі сұраққа ↓');

  String get summaryTitle => t(
    'Поздравляем с прохождением уровня!',
    'Деңгейді сәтті аяқтауыңызбен құттықтаймыз!',
  );
  String levelCompletedTitle(int id) =>
      t('Уровень $id пройден!', '$id-деңгей аяқталды!');
  String get levelCompletedSubtitle => t(
    'Поздравляем! Ваш ассистент освоил новое умение.',
    'Құттықтаймыз! Ассистентіңіз жаңа дағдыны меңгерді.',
  );
  String get whatChangedTitle => t('Что изменилось:', 'Не өзгерді:');
  String unlockedSkill(String name) =>
      t('Разблокирован модуль: $name', 'Модуль бұғаттан шығарылды: $name');
  String get configSaved => t(
    'Конфигурация зафиксирована в новой версии',
    'Конфигурация жаңа нұсқада бекітілді',
  );
  String get historySaved => t(
    'История версий и чатов сохранена без потерь',
    'Нұсқалар мен чаттар тарихы шығынсыз сақталды',
  );
  String get testInChatTitle =>
      t('Проверьте ассистента в деле', 'Ассистентті іс жүзінде тексеріңіз');
  String get testInChatSubtitle => t(
    'Откройте чат, задайте вопрос по теме уровня и оцените, как изменились его ответы.',
    'Чатты ашып, деңгей тақырыбы бойынша сұрақ қойыңыз және жауаптарының қалай өзгергенін бағалаңыз.',
  );
  String get testInChatBtn => t('Протестировать в чате', 'Чатта сынап көру');

  String get summaryBadge => t('Умение освоено', 'Дағды игерілді');
  String get nextStep => t('Следующий шаг', 'Келесі қадам');
  String get previousStep => t('Назад', 'Артқа');
  String get submitQuiz => t('Проверить ответы', 'Жауаптарды тексеру');
  String get retryQuiz => t('Попробовать снова', 'Қайта тапсыру');
  String get completeLevel => t('Завершить уровень', 'Деңгейді аяқтау');
  String get returnToCourse =>
      t('Вернуться к списку уровней', 'Деңгейлер тізіміне оралу');

  String get tryIdeaBtn => t('Попробовать', 'Байқап көру');
  String get nextUnderTheHoodBtn =>
      t('Далее: Под капотом', 'Келесі: Ішкі құрылымы');
  String get proceedToQuizBtn => t('Перейти к проверке', 'Тексеруге өту');
  String get proceedToSummaryBtn => t('К итогу уровня', 'Деңгей қорытындысына');
  String get nextLevelBtn => t('Следующий уровень', 'Келесі деңгей');
  String get finishCourseBtn => t('Завершить курс', 'Курсты аяқтау');

  String stepSemantics(int step, int total, String title) =>
      t('Шаг $step из $total: $title', '$total қадамның $step-қадамы: $title');
}
