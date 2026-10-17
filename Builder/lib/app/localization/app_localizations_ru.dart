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
}
