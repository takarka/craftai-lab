// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Craft Builder';

  @override
  String get assistantTab => 'Ассистент';

  @override
  String get courseTab => 'Курс';

  @override
  String get profileTab => 'Профиль';

  @override
  String get languageLabel => 'Язык интерфейса';

  @override
  String get starting => 'Запуск Craft Builder';

  @override
  String get configurationError =>
      'Не удалось запустить приложение с текущими настройками. Обратитесь в поддержку.';

  @override
  String get onboardingTitle => 'Ваш ассистент';

  @override
  String get onboardingPending =>
      'Настройка ассистента находится в разработке. Данные ещё не создаются и не отправляются.';

  @override
  String get assistantPending =>
      'Разговор с ассистентом появится после подключения CraftAI и локального хранилища.';

  @override
  String get coursePending =>
      'Курс находится в разработке. Учебный прогресс пока не создаётся.';

  @override
  String get profilePending =>
      'Профиль появится после подключения аккаунта CraftAI.';

  @override
  String get sessionUnavailable =>
      'Не удалось проверить сессию. Закройте и снова откройте приложение.';

  @override
  String get unavailableTitle => 'Страница недоступна';

  @override
  String get featurePending => 'Эта функция пока недоступна.';

  @override
  String get authIntro =>
      'Соберите собственного ИИ-ассистента и поймите, как он устроен.';

  @override
  String get authAccount => 'Аккаунт CraftAI';

  @override
  String get authEmail => 'Почта';

  @override
  String get authPassword => 'Пароль';

  @override
  String get authName => 'Имя';

  @override
  String get authConfirmPassword => 'Повторите пароль';

  @override
  String get authSignIn => 'Войти';

  @override
  String get authRegister => 'Создать аккаунт';

  @override
  String get authForgotPassword => 'Забыли пароль?';

  @override
  String get authBackToSignIn => 'Вернуться ко входу';

  @override
  String get authRecoveryTitle => 'Восстановление пароля';

  @override
  String get authRecoveryDescription =>
      'Укажите почту вашего аккаунта CraftAI. Мы отправим ссылку для смены пароля.';

  @override
  String get authSendReset => 'Отправить ссылку';

  @override
  String get authCheckInbox => 'Проверьте почту';

  @override
  String get authResetSent =>
      'Если аккаунт с этой почтой существует, на неё придёт ссылка для восстановления пароля. Проверьте также папку «Спам».';

  @override
  String get authUnavailable =>
      'Вход и регистрация пока недоступны. Подключение аккаунта CraftAI ещё не завершено.';

  @override
  String get authSharedAccount => 'Один аккаунт CraftAI для всех продуктов.';

  @override
  String get authPasswordHint =>
      'Используйте уникальный пароль для аккаунта CraftAI.';

  @override
  String get authAcceptDocuments =>
      'Я принимаю условия использования и политику конфиденциальности.';

  @override
  String get authTerms => 'Условия использования';

  @override
  String get authPrivacy => 'Политика конфиденциальности';

  @override
  String get authLegalUnavailable =>
      'Документы пока недоступны. До их публикации регистрация отключена.';

  @override
  String get authShowPassword => 'Показать пароль';

  @override
  String get authHidePassword => 'Скрыть пароль';

  @override
  String get authHeroLabel => 'Символ Craft Builder';

  @override
  String get fieldRequired => 'Заполните поле.';

  @override
  String get invalidEmail => 'Введите корректную почту.';

  @override
  String get passwordMismatch => 'Пароли не совпадают.';

  @override
  String get authInvalidCredentials => 'Неверная почта или пароль.';

  @override
  String get authAccountExists => 'У вас уже есть аккаунт CraftAI — войдите.';

  @override
  String get authWeakPassword =>
      'Пароль не соответствует требованиям CraftAI. Выберите более надёжный пароль.';

  @override
  String get authNetworkError =>
      'Не удалось подключиться. Проверьте интернет и попробуйте ещё раз.';

  @override
  String get authRateLimited => 'Слишком много попыток. Попробуйте позже.';

  @override
  String get authUnexpectedError =>
      'Не удалось выполнить действие. Попробуйте ещё раз.';

  @override
  String get closePage => 'Закрыть';

  @override
  String get authSubmitting => 'Отправка запроса';

  @override
  String get authResetPasswordTitle => 'Смена пароля';

  @override
  String get authNewPassword => 'Новый пароль';

  @override
  String get authSaveNewPassword => 'Сохранить пароль';

  @override
  String get authResetSuccess =>
      'Пароль успешно изменён. Теперь вы можете войти.';

  @override
  String get authInvalidResetLink =>
      'Ссылка для смены пароля недействительна или устарела. Запросите новую ссылку.';

  @override
  String get onbWelcomeTitle => 'Соберите своего ассистента';

  @override
  String get onbWelcomeBody =>
      'Пять уровней. На каждом ваш ассистент получает новое умение, а вы узнаёте, как он работает внутри.';

  @override
  String get onbBenefitWork => 'Учите ассистента своей работе';

  @override
  String get onbBenefitWorkBody =>
      'Инструкции, память и документы вашего предмета.';

  @override
  String get onbBenefitUnderstand => 'Понимайте каждый шаг';

  @override
  String get onbBenefitUnderstandBody =>
      'Разбирайте, что отправлено модели и откуда взялся ответ.';

  @override
  String get onbBenefitControl => 'Контролируйте данные';

  @override
  String get onbBenefitControlBody =>
      'Вы решаете, какие данные отправить и какие действия разрешить.';

  @override
  String get onbStart => 'Начать';

  @override
  String get onbNext => 'Далее';

  @override
  String get onbPreferencesTitle => 'Ваш предмет и классы';

  @override
  String get onbSubject => 'Предмет';

  @override
  String get onbSearchSubject => 'Найти предмет';

  @override
  String get onbNoSubjects =>
      'По этому запросу предметов нет. Выберите «Другое» и укажите свой предмет.';

  @override
  String get onbOtherSubject => 'Название вашего предмета';

  @override
  String get onbGrades => 'Классы';

  @override
  String get onbAssistantLanguage => 'Язык ассистента';

  @override
  String get onbRussian => 'Русский';

  @override
  String get onbKazakh => 'Казахский';

  @override
  String get onbBilingual => 'Русский и казахский';

  @override
  String get onbChooseSubject => 'Выберите предмет';

  @override
  String get onbChooseGrades => 'Выберите хотя бы один класс';

  @override
  String get onbSummaryTitle => 'Ваш выбор';

  @override
  String get onbCanChange => 'Эти настройки можно будет изменить позже.';

  @override
  String get onbMeetTitle => 'Встречайте вашего ассистента';

  @override
  String get onbMeetBody =>
      'Вы начнёте с базового ассистента. Новые умения будут появляться по мере прохождения курса.';

  @override
  String get onbName => 'Как назовёте ассистента?';

  @override
  String get onbCreate => 'Создать ассистента';

  @override
  String get onbCreating => 'Создание ассистента';

  @override
  String get onbStorageUnavailable =>
      'Сохранение ассистента пока недоступно. Настройки находятся только в текущем черновике.';

  @override
  String get onbLocalOnly =>
      'Эти настройки не отправляются модели автоматически.';

  @override
  String get onbSaveError =>
      'Не удалось сохранить ассистента. Ваш черновик остался на экране. Попробуйте ещё раз.';

  @override
  String get onbInvalidDraft => 'Проверьте предмет, классы и имя ассистента.';

  @override
  String get onbSessionChanged =>
      'Аккаунт изменился. Откройте настройку заново.';

  @override
  String get onbPreviewBanner =>
      'DEV · Предпросмотр онбординга. Данные только в памяти, без API.';

  @override
  String get onbHeroLabel => 'Базовый персонаж Craft Builder';

  @override
  String onbDefaultName(String subject) {
    return 'Ассистент: $subject';
  }

  @override
  String onbStep(int current, int total) {
    return 'Шаг $current из $total';
  }

  @override
  String onbGradeLabel(int grade) {
    return '$grade класс';
  }

  @override
  String get subjectMathematics => 'Математика';

  @override
  String get subjectRussian => 'Русский язык';

  @override
  String get subjectKazakh => 'Казахский язык';

  @override
  String get subjectEnglish => 'Английский язык';

  @override
  String get subjectHistory => 'История';

  @override
  String get subjectBiology => 'Биология';

  @override
  String get subjectGeography => 'География';

  @override
  String get subjectPhysics => 'Физика';

  @override
  String get subjectChemistry => 'Химия';

  @override
  String get subjectInformatics => 'Информатика';

  @override
  String get subjectPrimary => 'Начальные классы';

  @override
  String get subjectOther => 'Другое';

  @override
  String get d02Title => 'Запросы уходят за рубеж';

  @override
  String get d02Subtitle =>
      'Ваш вопрос, инструкция, память и найденные фрагменты документов отправляются к модели через сервер CraftAI. Сервер тексты не хранит.';

  @override
  String get d02StepPhone => 'Телефон';

  @override
  String get d02StepCraftAi => 'CraftAI';

  @override
  String get d02StepModel => 'Модель';

  @override
  String get d02Warning =>
      'Не отправляйте данные учеников: ФИО, оценки, диагнозы, контакты родителей.';

  @override
  String get d02Understand => 'Понятно';

  @override
  String get d02NotNow => 'Не сейчас';

  @override
  String get modelsTitle => 'Модель ассистента';

  @override
  String get modelsSubtitle =>
      'Категория определяет возможности, скорость и баланс мышления вашего ассистента.';

  @override
  String get modelsDisclaimer =>
      'Шкалы являются справочными и не гарантируют точность или время ответа.';

  @override
  String get modelsDataNotice => 'Данные за рубежом';

  @override
  String get modelsQuality => 'Качество';

  @override
  String get modelsSpeed => 'Скорость';

  @override
  String get modelsPrice => 'Стоимость';

  @override
  String get modelsRecommended => 'Рекомендуемая';

  @override
  String get modelsFastTitle => 'Быстрая';

  @override
  String get modelsFastDesc =>
      'Минимальная задержка, подходит для простых задач и быстрых ответов.';

  @override
  String get modelsStandardTitle => 'Рабочая';

  @override
  String get modelsStandardDesc =>
      'Оптимальный баланс глубины рассуждений, скорости и экономичности.';

  @override
  String get modelsAdvancedTitle => 'Мощная';

  @override
  String get modelsAdvancedDesc =>
      'Глубокий анализ сложных академических тем и нестандартных вопросов.';

  @override
  String get modelsUnavailableBadge => 'Временно недоступна';

  @override
  String get modelsUnavailableWarning =>
      'Выбранная категория сейчас недоступна на сервере. Рекомендуем переключиться на Рабочую категорию.';

  @override
  String get modelsSaveSuccess => 'Модель сохранена';
}
