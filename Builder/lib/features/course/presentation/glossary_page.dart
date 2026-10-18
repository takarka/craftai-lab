import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../ui_kit/ui_kit.dart';

class GlossaryTerm {
  const GlossaryTerm({
    required this.id,
    required this.term,
    this.termKk,
    required this.definition,
    this.definitionKk,
    required this.levelId,
    required this.category,
  });

  final String id;
  final String term;
  final String? termKk;
  final String definition;
  final String? definitionKk;
  final int levelId;
  final String category;

  String localizedTerm(bool isKk) => (isKk && termKk != null) ? termKk! : term;
  String localizedDefinition(bool isKk) =>
      (isKk && definitionKk != null) ? definitionKk! : definition;
}

class GlossaryPage extends StatefulWidget {
  final String? initialQuery;
  final String? fromLessonId;
  final String? fromTraceId;

  const GlossaryPage({
    super.key,
    this.initialQuery,
    this.fromLessonId,
    this.fromTraceId,
  });

  static const List<GlossaryTerm> terms = [
    GlossaryTerm(
      id: 'glossary.llm',
      term: 'Модель (LLM)',
      termKk: 'Модель (LLM)',
      definition:
          'Большая языковая модель — программа, которая генерирует текст по вероятностям на основе огромного объёма прочитанных данных.',
      definitionKk:
          'Үлкен тілдік модель — оқылған үлкен көлемдегі деректер негізінде ықтималдықтар бойынша мәтін құрастыратын бағдарлама.',
      levelId: 1,
      category: 'Основы',
    ),
    GlossaryTerm(
      id: 'glossary.prompt',
      term: 'Запрос (Prompt)',
      termKk: 'Сұраныс (Prompt)',
      definition:
          'Текст, который вы вводите в строку диалога. Чем точнее и подробнее описана задача, тем ближе ответ модели к ожиданиям.',
      definitionKk:
          'Диалог жолына енгізетін мәтін. Тапсырма неғұрлым нақты сипатталса, модель жауабы соғұрлым күткенге жақын болады.',
      levelId: 1,
      category: 'Основы',
    ),
    GlossaryTerm(
      id: 'glossary.system_instruction',
      term: 'Системный промпт (Инструкция)',
      termKk: 'Жүйелік промпт (Нұсқаулық)',
      definition:
          'Скрытые правила поведения, которые автоматически отправляются перед вопросом и задают роль, тон и ограничения ассистента.',
      definitionKk:
          'Сұрақ алдында автоматты түрде жіберілетін және ассистенттің рөлін, үні мен шектеулерін белгілейтін жасырын ережелер.',
      levelId: 2,
      category: 'Настройка',
    ),
    GlossaryTerm(
      id: 'glossary.context_window',
      term: 'Контекст (Context Window)',
      termKk: 'Контекст (Context Window)',
      definition:
          'Окно оперативной памяти модели: суммарный объём текста (инструкция + диалог + документы), который модель может удержать в один момент.',
      definitionKk:
          'Модельдің жедел жады терезесі: модель бір уақытта ұстай алатын мәтіннің жалпы көлемі (нұсқаулық + диалог + құжаттар).',
      levelId: 2,
      category: 'Основы',
    ),
    GlossaryTerm(
      id: 'glossary.token',
      term: 'Токен',
      termKk: 'Токен',
      definition:
          'Минимальная единица текста для нейросети (примерно 3–4 символа или корень слова). Расход токенов определяет стоимость и скорость работы.',
      definitionKk:
          'Нейрожелі үшін мәтіннің ең кіші бірлігі (шамамен 3–4 таңба не сөз түбірі). Токендер шығыны жұмыс құны мен жылдамдығын анықтайды.',
      levelId: 2,
      category: 'Архитектура',
    ),
    GlossaryTerm(
      id: 'glossary.rag',
      term: 'RAG (Retrieval-Augmented Generation)',
      termKk: 'RAG (Retrieval-Augmented Generation)',
      definition:
          'Технология поиска по вашим документам: нужные фрагменты сначала находятся в файле, а затем подставляются в запрос модели.',
      definitionKk:
          'Құжаттарыңыз бойынша іздеу технологиясы: қажетті үзінділер алдымен файлдан табылып, содан кейін модель сұранысына қосылады.',
      levelId: 3,
      category: 'Знания',
    ),
    GlossaryTerm(
      id: 'glossary.hallucination',
      term: 'Галлюцинация',
      termKk: 'Галлюцинация',
      definition:
          'Феномен, когда модель уверенным и грамотным тоном выдаёт вымышленные факты, цитаты или ложные научные данные.',
      definitionKk:
          'Модель сенімді әрі сауатты үнмен ойдан шығарылған деректерді, дәйексөздерді немесе жалған ғылыми мәліметтерді беретін құбылыс.',
      levelId: 3,
      category: 'Безопасность',
    ),
    GlossaryTerm(
      id: 'glossary.chunk',
      term: 'Чанк (Chunk)',
      termKk: 'Чанк (Фрагмент)',
      definition:
          'Небольшой смысловой фрагмент документа (обычно 1–2 абзаца), на которые приложение делит большой файл для быстрого семантического поиска.',
      definitionKk:
          'Жылдам семантикалық іздеу үшін үлкен файлды қолданба бөлетін құжаттың шағын мағыналық үзіндісі (әдетте 1–2 абзац).',
      levelId: 3,
      category: 'Знания',
    ),
    GlossaryTerm(
      id: 'glossary.long_term_memory',
      term: 'Долгая память',
      termKk: 'Ұзақ мерзімді жад',
      definition:
          'Факты о пользователе и классе, сохранённые в защищённой базе на телефоне, которые автоматически учитываются в любых новых беседах.',
      definitionKk:
          'Кез келген жаңа әңгімеде автоматты түрде ескерілетін телефондағы қорғалған базада сақталған пайдаланушы мен сынып туралы фактілер.',
      levelId: 4,
      category: 'Память',
    ),
    GlossaryTerm(
      id: 'glossary.function_calling',
      term: 'Инструмент (Function Calling)',
      termKk: 'Құрал (Function Calling)',
      definition:
          'Способность модели формировать запрос на действие (создать заметку, открыть ссылку), которое исполняет приложение после вашего одобрения.',
      definitionKk:
          'Модельдің сіздің мақұлдауыңыздан кейін қолданба орындайтын әрекетке сұрау қалыптастыру қабілеті (жазба жасау, сілтемені ашу).',
      levelId: 5,
      category: 'Действия',
    ),
    GlossaryTerm(
      id: 'glossary.mcp',
      term: 'MCP (Model Context Protocol)',
      termKk: 'MCP (Model Context Protocol)',
      definition:
          'Открытый международный стандарт безопасного подключения внешних баз знаний и сервисов к языковым моделям.',
      definitionKk:
          'Сыртқы білім базалары мен сервистерді тілдік модельдерге қауіпсіз қосудың ашық халықаралық стандарты.',
      levelId: 5,
      category: 'Действия',
    ),
  ];

  @override
  State<GlossaryPage> createState() => _GlossaryPageState();
}

class _GlossaryPageState extends State<GlossaryPage> {
  late final TextEditingController _searchController;
  late String _searchQuery;

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.initialQuery?.trim() ?? '';
    _searchController = TextEditingController(text: _searchQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isKk = Localizations.localeOf(context).languageCode == 'kk';
    final filtered = GlossaryPage.terms.where((t) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return t.term.toLowerCase().contains(q) ||
          (t.termKk != null && t.termKk!.toLowerCase().contains(q)) ||
          t.definition.toLowerCase().contains(q) ||
          (t.definitionKk != null &&
              t.definitionKk!.toLowerCase().contains(q)) ||
          t.category.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isKk ? 'ЖИ терминдер сөздігі' : 'Словарь терминов ИИ',
          style: BuilderType.h3,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.fromLessonId != null || widget.fromTraceId != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: BuilderColors.primaryTint,
                child: Row(
                  children: [
                    const Icon(
                      Icons.arrow_back,
                      size: 16,
                      color: BuilderColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.fromLessonId != null
                            ? (isKk
                                  ? '${widget.fromLessonId} сабағына оралу'
                                  : 'Вернуться к уроку ${widget.fromLessonId}')
                            : (isKk
                                  ? '${widget.fromTraceId} трейсіне оралу'
                                  : 'Вернуться к трейсу ${widget.fromTraceId}'),
                        style: BuilderType.small.copyWith(
                          color: BuilderColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('glossary.returnBtn'),
                      onPressed: () => context.pop(),
                      child: Text(isKk ? 'Оралу' : 'Назад'),
                    ),
                  ],
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const Key('glossary.searchField'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: isKk
                      ? 'Терминді не түсінікті іздеу...'
                      : 'Поиск термина или понятия...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        isKk ? 'Ештеңе табылмады' : 'Ничего не найдено',
                        style: BuilderType.body.copyWith(
                          color: BuilderColors.inkSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final t = filtered[index];
                        final displayTerm = t.localizedTerm(isKk);
                        final displayDef = t.localizedDefinition(isKk);

                        return BuilderCard(
                          key: ValueKey('glossary.term.${t.id}'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayTerm,
                                      style: BuilderType.h3,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: BuilderColors.primaryTint,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isKk
                                          ? 'Деңгей ${t.levelId}'
                                          : 'Уровень ${t.levelId}',
                                      style: BuilderType.small.copyWith(
                                        color: BuilderColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(displayDef, style: BuilderType.body),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      isKk
                                          ? 'Санат: ${t.category}'
                                          : 'Категория: ${t.category}',
                                      style: BuilderType.small.copyWith(
                                        color: BuilderColors.inkSecondary,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    key: Key('glossary.lessonBtn.${t.id}'),
                                    onPressed: () => context.push(
                                      '/course/lesson/${t.levelId}',
                                    ),
                                    child: Text(
                                      isKk ? 'Сабаққа өту' : 'К уроку',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
