import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../ui_kit/ui_kit.dart';

class GlossaryTerm {
  const GlossaryTerm({
    required this.term,
    required this.definition,
    required this.levelId,
    required this.category,
  });

  final String term;
  final String definition;
  final int levelId;
  final String category;
}

class GlossaryPage extends StatefulWidget {
  const GlossaryPage({super.key});

  static const List<GlossaryTerm> terms = [
    GlossaryTerm(
      term: 'Модель (LLM)',
      definition: 'Большая языковая модель — программа, которая генерирует текст по вероятностям на основе огромного объёма прочитанных данных.',
      levelId: 1,
      category: 'Основы',
    ),
    GlossaryTerm(
      term: 'Запрос (Prompt)',
      definition: 'Текст, который вы вводите в строку диалога. Чем точнее и подробнее описана задача, тем ближе ответ модели к ожиданиям.',
      levelId: 1,
      category: 'Основы',
    ),
    GlossaryTerm(
      term: 'Системный промпт (Инструкция)',
      definition: 'Скрытые правила поведения, которые автоматически отправляются перед вопросом и задают роль, тон и ограничения ассистента.',
      levelId: 2,
      category: 'Настройка',
    ),
    GlossaryTerm(
      term: 'Контекст (Context Window)',
      definition: 'Окно оперативной памяти модели: суммарный объём текста (инструкция + диалог + документы), который модель может удержать в один момент.',
      levelId: 2,
      category: 'Основы',
    ),
    GlossaryTerm(
      term: 'Токен',
      definition: 'Минимальная единица текста для нейросети (примерно 3–4 символа или корень слова). Расход токенов определяет стоимость и скорость работы.',
      levelId: 2,
      category: 'Архитектура',
    ),
    GlossaryTerm(
      term: 'RAG (Retrieval-Augmented Generation)',
      definition: 'Технология поиска по вашим документам: нужные фрагменты сначала находятся в файле, а затем подставляются в запрос модели.',
      levelId: 3,
      category: 'Знания',
    ),
    GlossaryTerm(
      term: 'Галлюцинация',
      definition: 'Феномен, когда модель уверенным и грамотным тоном выдаёт вымышленные факты, цитаты или ложные научные данные.',
      levelId: 3,
      category: 'Безопасность',
    ),
    GlossaryTerm(
      term: 'Чанк (Chunk)',
      definition: 'Небольшой смысловой фрагмент документа (обычно 1–2 абзаца), на которые приложение делит большой файл для быстрого семантического поиска.',
      levelId: 3,
      category: 'Знания',
    ),
    GlossaryTerm(
      term: 'Долгая память',
      definition: 'Факты о пользователе и классе, сохранённые в защищённой базе на телефоне, которые автоматически учитываются в любых новых беседах.',
      levelId: 4,
      category: 'Память',
    ),
    GlossaryTerm(
      term: 'Инструмент (Function Calling)',
      definition: 'Способность модели формировать запрос на действие (создать заметку, открыть ссылку), которое исполняет приложение после вашего одобрения.',
      levelId: 5,
      category: 'Действия',
    ),
    GlossaryTerm(
      term: 'MCP (Model Context Protocol)',
      definition: 'Открытый международный стандарт безопасного подключения внешних баз знаний и сервисов к языковым моделям.',
      levelId: 5,
      category: 'Действия',
    ),
    GlossaryTerm(
      term: 'Транскрибация',
      definition: 'Преобразование голосовой речи в печатный текст. Ошибки на этом этапе сразу искажают понимание модели.',
      levelId: 6,
      category: 'Голос',
    ),
    GlossaryTerm(
      term: 'Промпт-инъекция',
      definition: 'Вредоносный скрытый текст в чужих файлах или на сайтах, пытающийся заставить модель забыть ваши инструкции.',
      levelId: 8,
      category: 'Безопасность',
    ),
    GlossaryTerm(
      term: 'Автономный агент',
      definition: 'Система, которая сама разбивает задачу на шаги, выполняет их по очереди и проверяет результат без постоянного вмешательства.',
      levelId: 9,
      category: 'Агенты',
    ),
  ];

  @override
  State<GlossaryPage> createState() => _GlossaryPageState();
}

class _GlossaryPageState extends State<GlossaryPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = GlossaryPage.terms.where((t) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return t.term.toLowerCase().contains(q) ||
          t.definition.toLowerCase().contains(q) ||
          t.category.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Словарь терминов ИИ', style: BuilderType.h3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const Key('glossary.searchField'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Поиск термина или понятия...',
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                        'Ничего не найдено',
                        style: BuilderType.body.copyWith(color: BuilderColors.inkSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final t = filtered[index];
                        return BuilderCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(t.term, style: BuilderType.h3),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: BuilderColors.primaryTint,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Уровень ${t.levelId}',
                                      style: BuilderType.small.copyWith(
                                        color: BuilderColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(t.definition, style: BuilderType.body),
                              const SizedBox(height: 8),
                              Text(
                                'Категория: ${t.category}',
                                style: BuilderType.small.copyWith(color: BuilderColors.inkSecondary),
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
