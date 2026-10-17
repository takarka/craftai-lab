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

  /// No description provided for @authResetPasswordTitle.
  ///
  /// In ru, this message translates to:
  /// **'Смена пароля'**
  String get authResetPasswordTitle;

  /// No description provided for @authNewPassword.
  ///
  /// In ru, this message translates to:
  /// **'Новый пароль'**
  String get authNewPassword;

  /// No description provided for @authSaveNewPassword.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить пароль'**
  String get authSaveNewPassword;

  /// No description provided for @authResetSuccess.
  ///
  /// In ru, this message translates to:
  /// **'Пароль успешно изменён. Теперь вы можете войти.'**
  String get authResetSuccess;

  /// No description provided for @authInvalidResetLink.
  ///
  /// In ru, this message translates to:
  /// **'Ссылка для смены пароля недействительна или устарела. Запросите новую ссылку.'**
  String get authInvalidResetLink;

  /// No description provided for @onbWelcomeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Соберите своего ассистента'**
  String get onbWelcomeTitle;

  /// No description provided for @onbWelcomeBody.
  ///
  /// In ru, this message translates to:
  /// **'Пять уровней. На каждом ваш ассистент получает новое умение, а вы узнаёте, как он работает внутри.'**
  String get onbWelcomeBody;

  /// No description provided for @onbBenefitWork.
  ///
  /// In ru, this message translates to:
  /// **'Учите ассистента своей работе'**
  String get onbBenefitWork;

  /// No description provided for @onbBenefitWorkBody.
  ///
  /// In ru, this message translates to:
  /// **'Инструкции, память и документы вашего предмета.'**
  String get onbBenefitWorkBody;

  /// No description provided for @onbBenefitUnderstand.
  ///
  /// In ru, this message translates to:
  /// **'Понимайте каждый шаг'**
  String get onbBenefitUnderstand;

  /// No description provided for @onbBenefitUnderstandBody.
  ///
  /// In ru, this message translates to:
  /// **'Разбирайте, что отправлено модели и откуда взялся ответ.'**
  String get onbBenefitUnderstandBody;

  /// No description provided for @onbBenefitControl.
  ///
  /// In ru, this message translates to:
  /// **'Контролируйте данные'**
  String get onbBenefitControl;

  /// No description provided for @onbBenefitControlBody.
  ///
  /// In ru, this message translates to:
  /// **'Вы решаете, какие данные отправить и какие действия разрешить.'**
  String get onbBenefitControlBody;

  /// No description provided for @onbStart.
  ///
  /// In ru, this message translates to:
  /// **'Начать'**
  String get onbStart;

  /// No description provided for @onbNext.
  ///
  /// In ru, this message translates to:
  /// **'Далее'**
  String get onbNext;

  /// No description provided for @onbPreferencesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ваш предмет и классы'**
  String get onbPreferencesTitle;

  /// No description provided for @onbSubject.
  ///
  /// In ru, this message translates to:
  /// **'Предмет'**
  String get onbSubject;

  /// No description provided for @onbSearchSubject.
  ///
  /// In ru, this message translates to:
  /// **'Найти предмет'**
  String get onbSearchSubject;

  /// No description provided for @onbNoSubjects.
  ///
  /// In ru, this message translates to:
  /// **'По этому запросу предметов нет. Выберите «Другое» и укажите свой предмет.'**
  String get onbNoSubjects;

  /// No description provided for @onbOtherSubject.
  ///
  /// In ru, this message translates to:
  /// **'Название вашего предмета'**
  String get onbOtherSubject;

  /// No description provided for @onbGrades.
  ///
  /// In ru, this message translates to:
  /// **'Классы'**
  String get onbGrades;

  /// No description provided for @onbAssistantLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Язык ассистента'**
  String get onbAssistantLanguage;

  /// No description provided for @onbRussian.
  ///
  /// In ru, this message translates to:
  /// **'Русский'**
  String get onbRussian;

  /// No description provided for @onbKazakh.
  ///
  /// In ru, this message translates to:
  /// **'Казахский'**
  String get onbKazakh;

  /// No description provided for @onbBilingual.
  ///
  /// In ru, this message translates to:
  /// **'Русский и казахский'**
  String get onbBilingual;

  /// No description provided for @onbChooseSubject.
  ///
  /// In ru, this message translates to:
  /// **'Выберите предмет'**
  String get onbChooseSubject;

  /// No description provided for @onbChooseGrades.
  ///
  /// In ru, this message translates to:
  /// **'Выберите хотя бы один класс'**
  String get onbChooseGrades;

  /// No description provided for @onbSummaryTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ваш выбор'**
  String get onbSummaryTitle;

  /// No description provided for @onbCanChange.
  ///
  /// In ru, this message translates to:
  /// **'Эти настройки можно будет изменить позже.'**
  String get onbCanChange;

  /// No description provided for @onbMeetTitle.
  ///
  /// In ru, this message translates to:
  /// **'Встречайте вашего ассистента'**
  String get onbMeetTitle;

  /// No description provided for @onbMeetBody.
  ///
  /// In ru, this message translates to:
  /// **'Вы начнёте с базового ассистента. Новые умения будут появляться по мере прохождения курса.'**
  String get onbMeetBody;

  /// No description provided for @onbName.
  ///
  /// In ru, this message translates to:
  /// **'Как назовёте ассистента?'**
  String get onbName;

  /// No description provided for @onbCreate.
  ///
  /// In ru, this message translates to:
  /// **'Создать ассистента'**
  String get onbCreate;

  /// No description provided for @onbCreating.
  ///
  /// In ru, this message translates to:
  /// **'Создание ассистента'**
  String get onbCreating;

  /// No description provided for @onbStorageUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Сохранение ассистента пока недоступно. Настройки находятся только в текущем черновике.'**
  String get onbStorageUnavailable;

  /// No description provided for @onbLocalOnly.
  ///
  /// In ru, this message translates to:
  /// **'Эти настройки не отправляются модели автоматически.'**
  String get onbLocalOnly;

  /// No description provided for @onbSaveError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить ассистента. Ваш черновик остался на экране. Попробуйте ещё раз.'**
  String get onbSaveError;

  /// No description provided for @onbInvalidDraft.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте предмет, классы и имя ассистента.'**
  String get onbInvalidDraft;

  /// No description provided for @onbSessionChanged.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт изменился. Откройте настройку заново.'**
  String get onbSessionChanged;

  /// No description provided for @onbPreviewBanner.
  ///
  /// In ru, this message translates to:
  /// **'DEV · Предпросмотр онбординга. Данные только в памяти, без API.'**
  String get onbPreviewBanner;

  /// No description provided for @onbHeroLabel.
  ///
  /// In ru, this message translates to:
  /// **'Базовый персонаж Craft Builder'**
  String get onbHeroLabel;

  /// No description provided for @onbDefaultName.
  ///
  /// In ru, this message translates to:
  /// **'Ассистент: {subject}'**
  String onbDefaultName(String subject);

  /// No description provided for @onbStep.
  ///
  /// In ru, this message translates to:
  /// **'Шаг {current} из {total}'**
  String onbStep(int current, int total);

  /// No description provided for @onbGradeLabel.
  ///
  /// In ru, this message translates to:
  /// **'{grade} класс'**
  String onbGradeLabel(int grade);

  /// No description provided for @subjectMathematics.
  ///
  /// In ru, this message translates to:
  /// **'Математика'**
  String get subjectMathematics;

  /// No description provided for @subjectRussian.
  ///
  /// In ru, this message translates to:
  /// **'Русский язык'**
  String get subjectRussian;

  /// No description provided for @subjectKazakh.
  ///
  /// In ru, this message translates to:
  /// **'Казахский язык'**
  String get subjectKazakh;

  /// No description provided for @subjectEnglish.
  ///
  /// In ru, this message translates to:
  /// **'Английский язык'**
  String get subjectEnglish;

  /// No description provided for @subjectHistory.
  ///
  /// In ru, this message translates to:
  /// **'История'**
  String get subjectHistory;

  /// No description provided for @subjectBiology.
  ///
  /// In ru, this message translates to:
  /// **'Биология'**
  String get subjectBiology;

  /// No description provided for @subjectGeography.
  ///
  /// In ru, this message translates to:
  /// **'География'**
  String get subjectGeography;

  /// No description provided for @subjectPhysics.
  ///
  /// In ru, this message translates to:
  /// **'Физика'**
  String get subjectPhysics;

  /// No description provided for @subjectChemistry.
  ///
  /// In ru, this message translates to:
  /// **'Химия'**
  String get subjectChemistry;

  /// No description provided for @subjectInformatics.
  ///
  /// In ru, this message translates to:
  /// **'Информатика'**
  String get subjectInformatics;

  /// No description provided for @subjectPrimary.
  ///
  /// In ru, this message translates to:
  /// **'Начальные классы'**
  String get subjectPrimary;

  /// No description provided for @subjectOther.
  ///
  /// In ru, this message translates to:
  /// **'Другое'**
  String get subjectOther;

  /// No description provided for @d02Title.
  ///
  /// In ru, this message translates to:
  /// **'Запросы уходят за рубеж'**
  String get d02Title;

  /// No description provided for @d02Subtitle.
  ///
  /// In ru, this message translates to:
  /// **'Ваш вопрос, инструкция, память и найденные фрагменты документов отправляются к модели через сервер CraftAI. Сервер тексты не хранит.'**
  String get d02Subtitle;

  /// No description provided for @d02StepPhone.
  ///
  /// In ru, this message translates to:
  /// **'Телефон'**
  String get d02StepPhone;

  /// No description provided for @d02StepCraftAi.
  ///
  /// In ru, this message translates to:
  /// **'CraftAI'**
  String get d02StepCraftAi;

  /// No description provided for @d02StepModel.
  ///
  /// In ru, this message translates to:
  /// **'Модель'**
  String get d02StepModel;

  /// No description provided for @d02Warning.
  ///
  /// In ru, this message translates to:
  /// **'Не отправляйте данные учеников: ФИО, оценки, диагнозы, контакты родителей.'**
  String get d02Warning;

  /// No description provided for @d02Understand.
  ///
  /// In ru, this message translates to:
  /// **'Понятно'**
  String get d02Understand;

  /// No description provided for @d02NotNow.
  ///
  /// In ru, this message translates to:
  /// **'Не сейчас'**
  String get d02NotNow;

  /// No description provided for @modelsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Модель ассистента'**
  String get modelsTitle;

  /// No description provided for @modelsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Категория определяет возможности, скорость и баланс мышления вашего ассистента.'**
  String get modelsSubtitle;

  /// No description provided for @modelsDisclaimer.
  ///
  /// In ru, this message translates to:
  /// **'Шкалы являются справочными и не гарантируют точность или время ответа.'**
  String get modelsDisclaimer;

  /// No description provided for @modelsDataNotice.
  ///
  /// In ru, this message translates to:
  /// **'Данные за рубежом'**
  String get modelsDataNotice;

  /// No description provided for @modelsQuality.
  ///
  /// In ru, this message translates to:
  /// **'Качество'**
  String get modelsQuality;

  /// No description provided for @modelsSpeed.
  ///
  /// In ru, this message translates to:
  /// **'Скорость'**
  String get modelsSpeed;

  /// No description provided for @modelsPrice.
  ///
  /// In ru, this message translates to:
  /// **'Стоимость'**
  String get modelsPrice;

  /// No description provided for @modelsRecommended.
  ///
  /// In ru, this message translates to:
  /// **'Рекомендуемая'**
  String get modelsRecommended;

  /// No description provided for @modelsFastTitle.
  ///
  /// In ru, this message translates to:
  /// **'Быстрая'**
  String get modelsFastTitle;

  /// No description provided for @modelsFastDesc.
  ///
  /// In ru, this message translates to:
  /// **'Минимальная задержка, подходит для простых задач и быстрых ответов.'**
  String get modelsFastDesc;

  /// No description provided for @modelsStandardTitle.
  ///
  /// In ru, this message translates to:
  /// **'Рабочая'**
  String get modelsStandardTitle;

  /// No description provided for @modelsStandardDesc.
  ///
  /// In ru, this message translates to:
  /// **'Оптимальный баланс глубины рассуждений, скорости и экономичности.'**
  String get modelsStandardDesc;

  /// No description provided for @modelsAdvancedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Мощная'**
  String get modelsAdvancedTitle;

  /// No description provided for @modelsAdvancedDesc.
  ///
  /// In ru, this message translates to:
  /// **'Глубокий анализ сложных академических тем и нестандартных вопросов.'**
  String get modelsAdvancedDesc;

  /// No description provided for @modelsUnavailableBadge.
  ///
  /// In ru, this message translates to:
  /// **'Временно недоступна'**
  String get modelsUnavailableBadge;

  /// No description provided for @modelsUnavailableWarning.
  ///
  /// In ru, this message translates to:
  /// **'Выбранная категория сейчас недоступна на сервере. Рекомендуем переключиться на Рабочую категорию.'**
  String get modelsUnavailableWarning;

  /// No description provided for @modelsSaveSuccess.
  ///
  /// In ru, this message translates to:
  /// **'Модель сохранена'**
  String get modelsSaveSuccess;

  /// No description provided for @assistantSettingsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Настройки ассистента'**
  String get assistantSettingsTitle;

  /// No description provided for @assistantSettingsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Персонаж, возможности и локальные данные'**
  String get assistantSettingsSubtitle;

  /// No description provided for @assistantCharacterCardTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ваш ассистент'**
  String get assistantCharacterCardTitle;

  /// No description provided for @assistantEditName.
  ///
  /// In ru, this message translates to:
  /// **'Изменить имя'**
  String get assistantEditName;

  /// No description provided for @assistantLevelBadge.
  ///
  /// In ru, this message translates to:
  /// **'Уровень {level} из 5'**
  String assistantLevelBadge(int level);

  /// No description provided for @assistantModelRowTitle.
  ///
  /// In ru, this message translates to:
  /// **'Модель'**
  String get assistantModelRowTitle;

  /// No description provided for @assistantInstructionsCardTitle.
  ///
  /// In ru, this message translates to:
  /// **'Инструкции'**
  String get assistantInstructionsCardTitle;

  /// No description provided for @assistantInstructionsCardSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Правила поведения и тон общения'**
  String get assistantInstructionsCardSubtitle;

  /// No description provided for @assistantVersionsLink.
  ///
  /// In ru, this message translates to:
  /// **'История версий · v{version}'**
  String assistantVersionsLink(int version);

  /// No description provided for @assistantMemoryCardTitle.
  ///
  /// In ru, this message translates to:
  /// **'Память'**
  String get assistantMemoryCardTitle;

  /// No description provided for @assistantMemoryCardSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Сохранённые факты о классах и предмете'**
  String get assistantMemoryCardSubtitle;

  /// No description provided for @assistantDocumentsCardTitle.
  ///
  /// In ru, this message translates to:
  /// **'База знаний (документы)'**
  String get assistantDocumentsCardTitle;

  /// No description provided for @assistantDocumentsCardSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Локальные файлы и учебные материалы'**
  String get assistantDocumentsCardSubtitle;

  /// No description provided for @assistantToolsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Инструменты и MCP'**
  String get assistantToolsTitle;

  /// No description provided for @assistantToolsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Календарь, поиск и внешние сервисы'**
  String get assistantToolsSubtitle;

  /// No description provided for @assistantSkillsHeader.
  ///
  /// In ru, this message translates to:
  /// **'Возможности ассистента'**
  String get assistantSkillsHeader;

  /// No description provided for @assistantLocalDataRowTitle.
  ///
  /// In ru, this message translates to:
  /// **'Память и данные устройства'**
  String get assistantLocalDataRowTitle;

  /// No description provided for @assistantLocalDataRowSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Статистика хранения и политики'**
  String get assistantLocalDataRowSubtitle;

  /// No description provided for @assistantUndoLastChange.
  ///
  /// In ru, this message translates to:
  /// **'Отменить последнее изменение'**
  String get assistantUndoLastChange;

  /// No description provided for @assistantResetButton.
  ///
  /// In ru, this message translates to:
  /// **'Начать заново'**
  String get assistantResetButton;

  /// No description provided for @assistantNameTitle.
  ///
  /// In ru, this message translates to:
  /// **'Имя ассистента'**
  String get assistantNameTitle;

  /// No description provided for @assistantNameSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Как вы хотите называть своего помощника'**
  String get assistantNameSubtitle;

  /// No description provided for @assistantNameFieldLabel.
  ///
  /// In ru, this message translates to:
  /// **'Имя'**
  String get assistantNameFieldLabel;

  /// No description provided for @assistantNameFieldHint.
  ///
  /// In ru, this message translates to:
  /// **'Например: Сова, Арыстан, Ментор...'**
  String get assistantNameFieldHint;

  /// No description provided for @assistantNameGraphemeLimit.
  ///
  /// In ru, this message translates to:
  /// **'Максимум 30 символов'**
  String get assistantNameGraphemeLimit;

  /// No description provided for @assistantNameEmptyError.
  ///
  /// In ru, this message translates to:
  /// **'Имя не может быть пустым'**
  String get assistantNameEmptyError;

  /// No description provided for @assistantNameTooLongError.
  ///
  /// In ru, this message translates to:
  /// **'Имя превышает 30 символов'**
  String get assistantNameTooLongError;

  /// No description provided for @assistantVersionsTitle.
  ///
  /// In ru, this message translates to:
  /// **'История версий'**
  String get assistantVersionsTitle;

  /// No description provided for @assistantVersionsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Снимки настроек, правил и умений'**
  String get assistantVersionsSubtitle;

  /// No description provided for @assistantVersionCurrent.
  ///
  /// In ru, this message translates to:
  /// **'Текущая'**
  String get assistantVersionCurrent;

  /// No description provided for @assistantVersionSaveManual.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить версию'**
  String get assistantVersionSaveManual;

  /// No description provided for @assistantVersionSaveReasonHint.
  ///
  /// In ru, this message translates to:
  /// **'Причина сохранения (необязательно)'**
  String get assistantVersionSaveReasonHint;

  /// No description provided for @assistantVersionMissingResources.
  ///
  /// In ru, this message translates to:
  /// **'Частично доступно (удалены файлы)'**
  String get assistantVersionMissingResources;

  /// No description provided for @rollbackDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить версию {version}?'**
  String rollbackDialogTitle(int version);

  /// No description provided for @rollbackDialogSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Ассистент вернётся к состоянию на момент создания снимка.'**
  String get rollbackDialogSubtitle;

  /// No description provided for @rollbackWhatWillChange.
  ///
  /// In ru, this message translates to:
  /// **'Что изменится:'**
  String get rollbackWhatWillChange;

  /// No description provided for @rollbackWhatWillKeep.
  ///
  /// In ru, this message translates to:
  /// **'Что сохранится:'**
  String get rollbackWhatWillKeep;

  /// No description provided for @rollbackKeepHistory.
  ///
  /// In ru, this message translates to:
  /// **'История разговоров и прогресс курса не теряются'**
  String get rollbackKeepHistory;

  /// No description provided for @rollbackMissingResourcesWarning.
  ///
  /// In ru, this message translates to:
  /// **'Некоторые документы были физически удалены и не будут восстановлены.'**
  String get rollbackMissingResourcesWarning;

  /// No description provided for @rollbackConfirmButton.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить'**
  String get rollbackConfirmButton;

  /// No description provided for @rollbackCancelButton.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get rollbackCancelButton;

  /// No description provided for @rollbackSuccess.
  ///
  /// In ru, this message translates to:
  /// **'Версия {version} успешно восстановлена'**
  String rollbackSuccess(int version);

  /// No description provided for @localDataTitle.
  ///
  /// In ru, this message translates to:
  /// **'Память и данные'**
  String get localDataTitle;

  /// No description provided for @localDataSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Локальное хранилище и политики очистки'**
  String get localDataSubtitle;

  /// No description provided for @localDataDeviceWarning.
  ///
  /// In ru, this message translates to:
  /// **'Все данные хранятся только на этом устройстве. При удалении приложения они будут безвозвратно удалены.'**
  String get localDataDeviceWarning;

  /// No description provided for @localDataMapHeader.
  ///
  /// In ru, this message translates to:
  /// **'Карта сохранённых данных'**
  String get localDataMapHeader;

  /// No description provided for @localDataConversations.
  ///
  /// In ru, this message translates to:
  /// **'Разговоры и сообщения: {count}'**
  String localDataConversations(int count);

  /// No description provided for @localDataMemoryFacts.
  ///
  /// In ru, this message translates to:
  /// **'Факты в памяти: {count}'**
  String localDataMemoryFacts(int count);

  /// No description provided for @localDataDocuments.
  ///
  /// In ru, this message translates to:
  /// **'Документы и индексы: {count}'**
  String localDataDocuments(int count);

  /// No description provided for @localDataTraces.
  ///
  /// In ru, this message translates to:
  /// **'Трассировки запросов: {count}'**
  String localDataTraces(int count);

  /// No description provided for @localDataVersions.
  ///
  /// In ru, this message translates to:
  /// **'История версий: {count}'**
  String localDataVersions(int count);

  /// No description provided for @localDataRetentionHeader.
  ///
  /// In ru, this message translates to:
  /// **'Политика хранения'**
  String get localDataRetentionHeader;

  /// No description provided for @localDataRetention30Days.
  ///
  /// In ru, this message translates to:
  /// **'30 дней'**
  String get localDataRetention30Days;

  /// No description provided for @localDataRetention90Days.
  ///
  /// In ru, this message translates to:
  /// **'90 дней'**
  String get localDataRetention90Days;

  /// No description provided for @localDataRetentionForever.
  ///
  /// In ru, this message translates to:
  /// **'Бессрочно'**
  String get localDataRetentionForever;

  /// No description provided for @localDataRetentionSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Автоматическое удаление старых разговоров'**
  String get localDataRetentionSubtitle;

  /// No description provided for @resetDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить ассистента?'**
  String get resetDialogTitle;

  /// No description provided for @resetDialogSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Это действие безвозвратно удалит все локальные материалы ассистента.'**
  String get resetDialogSubtitle;

  /// No description provided for @resetWhatWillBeDeleted.
  ///
  /// In ru, this message translates to:
  /// **'Будет удалено:'**
  String get resetWhatWillBeDeleted;

  /// No description provided for @resetDeleteInstructions.
  ///
  /// In ru, this message translates to:
  /// **'Имя, инструкции и конфигурация ассистента'**
  String get resetDeleteInstructions;

  /// No description provided for @resetDeleteConversations.
  ///
  /// In ru, this message translates to:
  /// **'Вся история разговоров и сообщений'**
  String get resetDeleteConversations;

  /// No description provided for @resetDeleteMemory.
  ///
  /// In ru, this message translates to:
  /// **'Все сохранённые факты памяти'**
  String get resetDeleteMemory;

  /// No description provided for @resetDeleteDocuments.
  ///
  /// In ru, this message translates to:
  /// **'Все загруженные документы и фрагменты знаний'**
  String get resetDeleteDocuments;

  /// No description provided for @resetDeleteVersions.
  ///
  /// In ru, this message translates to:
  /// **'Вся история версий'**
  String get resetDeleteVersions;

  /// No description provided for @resetDeleteTraces.
  ///
  /// In ru, this message translates to:
  /// **'Все технические трассировки запросов'**
  String get resetDeleteTraces;

  /// No description provided for @resetWhatWillStay.
  ///
  /// In ru, this message translates to:
  /// **'Что сохранится:'**
  String get resetWhatWillStay;

  /// No description provided for @resetKeepAccount.
  ///
  /// In ru, this message translates to:
  /// **'Ваш аккаунт CraftAI и активная сессия'**
  String get resetKeepAccount;

  /// No description provided for @resetKeepD02.
  ///
  /// In ru, this message translates to:
  /// **'Согласие на трансграничную передачу данных (D02)'**
  String get resetKeepD02;

  /// No description provided for @resetTypeConfirmationPrompt.
  ///
  /// In ru, this message translates to:
  /// **'Для подтверждения введите слово «{word}»:'**
  String resetTypeConfirmationPrompt(String word);

  /// No description provided for @resetConfirmationWord.
  ///
  /// In ru, this message translates to:
  /// **'СБРОС'**
  String get resetConfirmationWord;

  /// No description provided for @resetConfirmButton.
  ///
  /// In ru, this message translates to:
  /// **'Удалить всё и сбросить'**
  String get resetConfirmButton;

  /// No description provided for @resetCancelButton.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get resetCancelButton;

  /// No description provided for @resetInProgress.
  ///
  /// In ru, this message translates to:
  /// **'Выполняется сброс ассистента...'**
  String get resetInProgress;
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
