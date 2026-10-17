// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kazakh (`kk`).
class AppLocalizationsKk extends AppLocalizations {
  AppLocalizationsKk([String locale = 'kk']) : super(locale);

  @override
  String get appTitle => 'Craft Builder';

  @override
  String get assistantTab => 'Ассистент';

  @override
  String get courseTab => 'Курс';

  @override
  String get profileTab => 'Профиль';

  @override
  String get languageLabel => 'Интерфейс тілі';

  @override
  String get starting => 'Craft Builder іске қосылуда';

  @override
  String get configurationError =>
      'Қолданбаны ағымдағы баптаулармен іске қосу мүмкін болмады. Қолдау қызметіне хабарласыңыз.';

  @override
  String get signInPending =>
      'Craft Builder қолданбасына қош келдіңіз. CraftAI аккаунты арқылы кіру әзірге қолжетімсіз: авторизацияны қосу жұмысы жүріп жатыр.';

  @override
  String get onboardingTitle => 'Сіздің ассистентіңіз';

  @override
  String get onboardingPending =>
      'Ассистентті баптау әзірленіп жатыр. Деректер әлі жасалмайды және жіберілмейді.';

  @override
  String get assistantPending =>
      'Ассистентпен сөйлесу CraftAI мен жергілікті сақтау орны қосылғаннан кейін қолжетімді болады.';

  @override
  String get coursePending =>
      'Курс әзірленіп жатыр. Оқу барысы әзірге сақталмайды.';

  @override
  String get profilePending =>
      'Профиль CraftAI аккаунты қосылғаннан кейін қолжетімді болады.';

  @override
  String get sessionUnavailable =>
      'Сессияны тексеру мүмкін болмады. Қолданбаны жауып, қайта ашыңыз.';

  @override
  String get unavailableTitle => 'Бет қолжетімсіз';

  @override
  String get featurePending => 'Бұл мүмкіндік әзірге қолжетімсіз.';
}
