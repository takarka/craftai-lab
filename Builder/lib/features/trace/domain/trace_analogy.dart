import 'package:flutter/foundation.dart';

@immutable
class AnalogyItem {
  final String lifeTerm;
  final String assistantTerm;
  final String iconName;

  const AnalogyItem({
    required this.lifeTerm,
    required this.assistantTerm,
    required this.iconName,
  });
}

@immutable
class TraceAnalogy {
  final String title;
  final String story;
  final String subtitle;
  final List<AnalogyItem> items;
  final String takeawayTitle;
  final String takeawayText;

  const TraceAnalogy({
    required this.title,
    required this.story,
    required this.subtitle,
    required this.items,
    required this.takeawayTitle,
    required this.takeawayText,
  });

  static TraceAnalogy getForLanguage(String languageCode) {
    if (languageCode.toLowerCase() == 'kk') {
      return const TraceAnalogy(
        title: 'Хатшы және сарапшы',
        story: 'Елестетіңіз: сіз хатшыдан тексеру жұмысын дайындауды сұрайсыз. Хатшы оны өзі жазбайды. Ол барлық қажетті құжаттарды бір бумаға жинап, басқа қаладағы сарапшының үстеліне қояды.',
        subtitle: 'Өмірде → ассистентте',
        items: [
          AnalogyItem(
            lifeTerm: 'Хатшы',
            assistantTerm: 'Қосымша',
            iconName: 'phone',
          ),
          AnalogyItem(
            lifeTerm: 'Ережелер салынған бума',
            assistantTerm: 'Нұсқаулық',
            iconName: 'folder',
          ),
          AnalogyItem(
            lifeTerm: 'Сынып жайлы жазба дәптері',
            assistantTerm: 'Жад',
            iconName: 'lightbulb',
          ),
          AnalogyItem(
            lifeTerm: 'Оқулықтағы бетбелгілер',
            assistantTerm: 'Табылған құжаттар',
            iconName: 'bookmark',
          ),
          AnalogyItem(
            lifeTerm: 'Басқа қаладағы сарапшы',
            assistantTerm: 'Модель',
            iconName: 'server',
          ),
        ],
        takeawayTitle: 'Ең бастысы:',
        takeawayText: 'Сарапшы өткен сөйлесулерді есте сақтамайды. Ол үстелде не жатқанын ғана көреді. Сондықтан хатшы буманы әр сұраныс сайын қайтадан жинайды.',
      );
    }

    return const TraceAnalogy(
      title: 'Секретарь и эксперт',
      story: 'Представьте: вы просите секретаря подготовить проверочную. Секретарь не пишет её сам. Он собирает папку и кладёт на стол эксперту, который сидит в другом городе.',
      subtitle: 'В жизни → в ассистенте',
      items: [
        AnalogyItem(
          lifeTerm: 'Секретарь',
          assistantTerm: 'Приложение',
          iconName: 'phone',
        ),
        AnalogyItem(
          lifeTerm: 'Папка с вашими правилами',
          assistantTerm: 'Инструкция',
          iconName: 'folder',
        ),
        AnalogyItem(
          lifeTerm: 'Блокнот с фактами о классе',
          assistantTerm: 'Память',
          iconName: 'lightbulb',
        ),
        AnalogyItem(
          lifeTerm: 'Закладки в учебнике',
          assistantTerm: 'Найденные документы',
          iconName: 'bookmark',
        ),
        AnalogyItem(
          lifeTerm: 'Эксперт в другом городе',
          assistantTerm: 'Модель',
          iconName: 'server',
        ),
      ],
      takeawayTitle: 'Главное:',
      takeawayText: 'Эксперт не помнит прошлых разговоров. Он видит только то, что лежит на столе. Поэтому секретарь каждый раз собирает папку заново.',
    );
  }
}
