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

  /// No description provided for @signInPending.
  ///
  /// In ru, this message translates to:
  /// **'Добро пожаловать в Craft Builder. Вход через аккаунт CraftAI пока недоступен: подключение авторизации находится в разработке.'**
  String get signInPending;

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
