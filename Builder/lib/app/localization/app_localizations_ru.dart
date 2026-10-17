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
  String get signInPending =>
      'Добро пожаловать в Craft Builder. Вход через аккаунт CraftAI пока недоступен: подключение авторизации находится в разработке.';

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
}
