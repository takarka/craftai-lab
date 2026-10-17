import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_kk.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'localization/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ru'),
    Locale('kk'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ru, this message translates to:
  /// **'Craft Builder'**
  String get appTitle;

  /// No description provided for @assistantTab.
  ///
  /// In ru, this message translates to:
  /// **'Ассистент'**
  String get assistantTab;

  /// No description provided for @courseTab.
  ///
  /// In ru, this message translates to:
  /// **'Курс'**
  String get courseTab;

  /// No description provided for @profileTab.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get profileTab;

  /// No description provided for @languageLabel.
  ///
  /// In ru, this message translates to:
  /// **'Язык интерфейса'**
  String get languageLabel;

  /// No description provided for @starting.
  ///
  /// In ru, this message translates to:
  /// **'Запуск Craft Builder'**
  String get starting;

  /// No description provided for @configurationError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось запустить приложение с текущими настройками. Обратитесь в поддержку.'**
  String get configurationError;

  /// No description provided for @onboardingTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ваш ассистент'**
  String get onboardingTitle;

  /// No description provided for @onboardingPending.
  ///
  /// In ru, this message translates to:
  /// **'Настройка ассистента находится в разработке. Данные ещё не создаются и не отправляются.'**
  String get onboardingPending;

  /// No description provided for @assistantPending.
  ///
  /// In ru, this message translates to:
  /// **'Разговор с ассистентом появится после подключения CraftAI и локального хранилища.'**
  String get assistantPending;

  /// No description provided for @coursePending.
  ///
  /// In ru, this message translates to:
  /// **'Курс находится в разработке. Учебный прогресс пока не создаётся.'**
  String get coursePending;

  /// No description provided for @profilePending.
  ///
  /// In ru, this message translates to:
  /// **'Профиль появится после подключения аккаунта CraftAI.'**
  String get profilePending;

  /// No description provided for @sessionUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось проверить сессию. Закройте и снова откройте приложение.'**
  String get sessionUnavailable;

  /// No description provided for @unavailableTitle.
  ///
  /// In ru, this message translates to:
  /// **'Страница недоступна'**
  String get unavailableTitle;

  /// No description provided for @featurePending.
  ///
  /// In ru, this message translates to:
  /// **'Эта функция пока недоступна.'**
  String get featurePending;

  /// No description provided for @authIntro.
  ///
  /// In ru, this message translates to:
  /// **'Соберите собственного ИИ-ассистента и поймите, как он устроен.'**
  String get authIntro;

  /// No description provided for @authAccount.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт CraftAI'**
  String get authAccount;

  /// No description provided for @authEmail.
  ///
  /// In ru, this message translates to:
  /// **'Почта'**
  String get authEmail;

  /// No description provided for @authPassword.
  ///
  /// In ru, this message translates to:
  /// **'Пароль'**
  String get authPassword;

  /// No description provided for @authName.
  ///
  /// In ru, this message translates to:
  /// **'Имя'**
  String get authName;

  /// No description provided for @authConfirmPassword.
  ///
  /// In ru, this message translates to:
  /// **'Повторите пароль'**
  String get authConfirmPassword;

  /// No description provided for @authSignIn.
  ///
  /// In ru, this message translates to:
  /// **'Войти'**
  String get authSignIn;

  /// No description provided for @authRegister.
  ///
  /// In ru, this message translates to:
  /// **'Создать аккаунт'**
  String get authRegister;

  /// No description provided for @authForgotPassword.
  ///
  /// In ru, this message translates to:
  /// **'Забыли пароль?'**
  String get authForgotPassword;

  /// No description provided for @authBackToSignIn.
  ///
  /// In ru, this message translates to:
  /// **'Вернуться ко входу'**
  String get authBackToSignIn;

  /// No description provided for @authRecoveryTitle.
  ///
  /// In ru, this message translates to:
  /// **'Восстановление пароля'**
  String get authRecoveryTitle;

  /// No description provided for @authRecoveryDescription.
  ///
  /// In ru, this message translates to:
  /// **'Укажите почту вашего аккаунта CraftAI. Мы отправим ссылку для смены пароля.'**
  String get authRecoveryDescription;

  /// No description provided for @authSendReset.
  ///
  /// In ru, this message translates to:
  /// **'Отправить ссылку'**
  String get authSendReset;

  /// No description provided for @authCheckInbox.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте почту'**
  String get authCheckInbox;

  /// No description provided for @authResetSent.
  ///
  /// In ru, this message translates to:
  /// **'Если аккаунт с этой почтой существует, на неё придёт ссылка для восстановления пароля. Проверьте также папку «Спам».'**
  String get authResetSent;

  /// No description provided for @authUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Вход и регистрация пока недоступны. Подключение аккаунта CraftAI ещё не завершено.'**
  String get authUnavailable;

  /// No description provided for @authSharedAccount.
  ///
  /// In ru, this message translates to:
  /// **'Один аккаунт CraftAI для всех продуктов.'**
  String get authSharedAccount;

  /// No description provided for @authPasswordHint.
  ///
  /// In ru, this message translates to:
  /// **'Используйте уникальный пароль для аккаунта CraftAI.'**
  String get authPasswordHint;

  /// No description provided for @authAcceptDocuments.
  ///
  /// In ru, this message translates to:
  /// **'Я принимаю условия использования и политику конфиденциальности.'**
  String get authAcceptDocuments;

  /// No description provided for @authTerms.
  ///
  /// In ru, this message translates to:
  /// **'Условия использования'**
  String get authTerms;

  /// No description provided for @authPrivacy.
  ///
  /// In ru, this message translates to:
  /// **'Политика конфиденциальности'**
  String get authPrivacy;

  /// No description provided for @authLegalUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Документы пока недоступны. До их публикации регистрация отключена.'**
  String get authLegalUnavailable;

  /// No description provided for @authShowPassword.
  ///
  /// In ru, this message translates to:
  /// **'Показать пароль'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть пароль'**
  String get authHidePassword;

  /// No description provided for @authHeroLabel.
  ///
  /// In ru, this message translates to:
  /// **'Символ Craft Builder'**
  String get authHeroLabel;

  /// No description provided for @fieldRequired.
  ///
  /// In ru, this message translates to:
  /// **'Заполните поле.'**
  String get fieldRequired;

  /// No description provided for @invalidEmail.
  ///
  /// In ru, this message translates to:
  /// **'Введите корректную почту.'**
  String get invalidEmail;

  /// No description provided for @passwordMismatch.
  ///
  /// In ru, this message translates to:
  /// **'Пароли не совпадают.'**
  String get passwordMismatch;

  /// No description provided for @authInvalidCredentials.
  ///
  /// In ru, this message translates to:
  /// **'Неверная почта или пароль.'**
  String get authInvalidCredentials;

  /// No description provided for @authAccountExists.
  ///
  /// In ru, this message translates to:
  /// **'У вас уже есть аккаунт CraftAI — войдите.'**
  String get authAccountExists;

  /// No description provided for @authWeakPassword.
  ///
  /// In ru, this message translates to:
  /// **'Пароль не соответствует требованиям CraftAI. Выберите более надёжный пароль.'**
  String get authWeakPassword;

  /// No description provided for @authNetworkError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось подключиться. Проверьте интернет и попробуйте ещё раз.'**
  String get authNetworkError;

  /// No description provided for @authRateLimited.
  ///
  /// In ru, this message translates to:
  /// **'Слишком много попыток. Попробуйте позже.'**
  String get authRateLimited;

  /// No description provided for @authUnexpectedError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось выполнить действие. Попробуйте ещё раз.'**
  String get authUnexpectedError;

  /// No description provided for @closePage.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get closePage;

  /// No description provided for @authSubmitting.
  ///
  /// In ru, this message translates to:
  /// **'Отправка запроса'**
  String get authSubmitting;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['kk', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'kk':
      return AppLocalizationsKk();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
