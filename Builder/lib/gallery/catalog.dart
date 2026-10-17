import 'package:flutter/material.dart';
import '../ui_kit/ui_kit.dart';

const _sections = [
  ('Основы', 'Цвета, типографика, сетка', BuilderGlyph.settings, 'UK1'),
  ('Контролы', 'Кнопки и ввод', BuilderGlyph.tool, 'UK2'),
  ('Композиции', 'Навигация и карточки', BuilderGlyph.course, 'UK3'),
  ('Персонаж', 'Уровни и состояния', BuilderGlyph.robot, 'UK4'),
];

class BuilderCatalog extends StatefulWidget {
  const BuilderCatalog({super.key, this.initialSection = 0});
  final int initialSection;
  @override
  State<BuilderCatalog> createState() => _BuilderCatalogState();
}

class _BuilderCatalogState extends State<BuilderCatalog> {
  late int _section = widget.initialSection.clamp(0, 3);
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _section = index);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      final (title, subtitle, _, source) = _sections[_section];
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                Container(
                  width: 248,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      right: BorderSide(color: BuilderColors.line),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Brand(),
                      const SizedBox(height: 48),
                      const Padding(
                        padding: EdgeInsets.only(left: 12),
                        child: Text('БИБЛИОТЕКА', style: BuilderType.label),
                      ),
                      const SizedBox(height: 16),
                      for (var i = 0; i < _sections.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Semantics(
                            selected: i == _section,
                            child: Material(
                              color: i == _section
                                  ? BuilderColors.primaryTint
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _select(i),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      BuilderIcon(
                                        _sections[i].$3,
                                        size: 22,
                                        color: i == _section
                                            ? BuilderColors.primary
                                            : BuilderColors.inkSecondary,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _sections[i].$1,
                                          style: BuilderType.title.copyWith(
                                            color: i == _section
                                                ? BuilderColors.primary
                                                : BuilderColors.inkSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      const Divider(),
                      const SizedBox(height: 16),
                      const Text(
                        'Создано для учителей.',
                        style: BuilderType.title,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Коротко, крупно, спокойно.\nКаждый компонент — часть одной системы.',
                        style: BuilderType.small,
                      ),
                      const SizedBox(height: 20),
                      const BuilderBadge(
                        'Flutter · v0.1',
                        icon: BuilderGlyph.code,
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      color: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 36 : 16,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          if (!wide)
                            const Expanded(child: _Brand())
                          else
                            const Expanded(
                              child: Text(
                                'Дизайн-система / UI Kit',
                                style: BuilderType.small,
                              ),
                            ),
                          const BuilderBadge(
                            'MVP · 1–5',
                            icon: BuilderGlyph.bolt,
                          ),
                        ],
                      ),
                    ),
                    if (!wide)
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: DefaultTabController(
                          length: 4,
                          initialIndex: _section,
                          child: TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            dividerColor: Colors.transparent,
                            labelColor: BuilderColors.primary,
                            unselectedLabelColor: BuilderColors.inkSecondary,
                            labelStyle: BuilderType.title.copyWith(
                              fontSize: 14,
                            ),
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              color: BuilderColors.primaryTint,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onTap: _select,
                            tabs: [
                              for (final section in _sections)
                                Tab(text: section.$1),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: Scrollbar(
                        controller: _scroll,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          padding: EdgeInsets.all(wide ? 36 : 16),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1300),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      Text(
                                        'UI Kit',
                                        style: wide
                                            ? BuilderType.display
                                            : BuilderType.h1,
                                      ),
                                      BuilderBadge(
                                        '$source / 04',
                                        neutral: true,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(title, style: BuilderType.h2),
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    style: BuilderType.body.copyWith(
                                      color: BuilderColors.inkSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  switch (_section) {
                                    0 => const _Foundations(),
                                    1 => const _Controls(),
                                    2 => const _Compositions(),
                                    _ => const _Characters(),
                                  },
                                  const SizedBox(height: 32),
                                  const Divider(),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'CRAFT BUILDER · CRAFTAI',
                                    style: BuilderType.label,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Компоненты по макетам UK1–UK4 и требованиям Builder. Каталог демонстрирует интерфейс; запросы к ИИ и внешние действия не выполняются.',
                                    style: BuilderType.small,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      BuilderCharacter(size: 36, compact: true),
      SizedBox(width: 10),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Craft Builder', style: BuilderType.title),
            SizedBox(height: 2),
            Text('by CraftAI', style: BuilderType.small),
          ],
        ),
      ),
    ],
  );
}

Widget _stack(List<Widget> children, {double gap = 16}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (var i = 0; i < children.length; i++) ...[
      if (i > 0) SizedBox(height: gap),
      children[i],
    ],
  ],
);
void _toast(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.caption});
  final String title;
  final String? caption;
  final Widget child;
  @override
  Widget build(BuildContext context) => BuilderCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: BuilderType.h3),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(caption!, style: BuilderType.small),
        ],
        const SizedBox(height: 20),
        child,
      ],
    ),
  );
}

class _Columns extends StatelessWidget {
  const _Columns({required this.left, required this.right});
  final Widget left;
  final Widget right;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= 780
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 20),
              Expanded(child: right),
            ],
          )
        : _stack([left, right], gap: 20),
  );
}

class _Foundations extends StatelessWidget {
  const _Foundations();
  @override
  Widget build(BuildContext context) => _stack([
    Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: BuilderColors.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Один язык интерфейса.',
                  style: BuilderType.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  'Синий — действие. Оранжевый — внимание.\nПонятные состояния, спокойный ритм.',
                  style: BuilderType.body.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const BuilderCharacter(level: 5, size: 80),
        ],
      ),
    ),
    _Panel(
      title: '01 / Палитра',
      caption:
          'Точные значения из UK1. Статус всегда сопровождается текстом и иконкой.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = constraints.maxWidth < 420
              ? 2
              : constraints.maxWidth < 700
              ? 4
              : 8;
          final width = (constraints.maxWidth - (count - 1) * 12) / count;
          return Wrap(
            spacing: 12,
            runSpacing: 20,
            children: [
              for (final entry in BuilderColors.palette.entries)
                SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: entry.value,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: BuilderColors.ink.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.key,
                        style: BuilderType.small.copyWith(
                          color: BuilderColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '#${entry.value.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                        style: BuilderType.mono.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
    _Columns(
      left: _Panel(
        title: '02 / Типографика',
        caption: 'Onest · кириллица и қазақша. Шрифты встроены в приложение.',
        child: _stack([
          for (final (name, sample, style, spec) in [
            ('Display', 'Итог уровня', BuilderType.display, '34 / 40 · 700'),
            ('H1', 'Ваш ассистент', BuilderType.h1, '28 / 32 · 700'),
            ('H2', 'Курс', BuilderType.h2, '22 / 28 · 700'),
            ('H3', 'Настройки', BuilderType.h3, '18 / 24 · 700'),
            ('Title', 'Заголовок карточки', BuilderType.title, '16 / 20 · 700'),
            (
              'Body',
              'Попробуйте и сравните ответы.',
              BuilderType.body,
              '16 / 23 · 400',
            ),
            (
              'Small',
              'Өз көмекшіңізді жасаңыз',
              BuilderType.small,
              '13 / 18 · 400',
            ),
            ('Label', 'СЕКЦИЯ', BuilderType.label, '12 / 16 · 700'),
            ('Mono', 'v3 · 1 240 токенов', BuilderType.mono, '12.5 / 18 · 500'),
          ])
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name · $spec',
                  style: BuilderType.mono.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 8),
                Text(sample, style: style),
                const SizedBox(height: 8),
                const Divider(height: 1),
              ],
            ),
        ], gap: 16),
      ),
      right: _stack([
        _Panel(
          title: '03 / Ритм и форма',
          caption: 'Сетка с шагом 4 px. Минимальная цель нажатия — 44 × 44.',
          child: _stack([
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final space in BuilderSpace.scale)
                  Column(
                    children: [
                      Container(
                        width: space,
                        height: space,
                        decoration: BoxDecoration(
                          color: BuilderColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('${space.toInt()}', style: BuilderType.mono),
                    ],
                  ),
              ],
            ),
            const Divider(),
            Wrap(
              spacing: 14,
              runSpacing: 16,
              children: [
                for (final (radius, label) in [
                  (12.0, 'Контрол'),
                  (13.0, 'Чип'),
                  (14.0, 'Плитка'),
                  (18.0, 'Карточка'),
                  (24.0, 'Шторка'),
                ])
                  Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: BuilderColors.primaryTint,
                          border: Border.all(color: BuilderColors.primary),
                          borderRadius: BorderRadius.circular(radius),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${radius.toInt()} · $label',
                        style: BuilderType.small,
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(),
            const BuilderCard(
              child: Text(
                'Карточка · тень 0 / 1 / 2 · 8%',
                style: BuilderType.small,
              ),
            ),
            const BuilderCard(
              selected: true,
              child: Text('Выбрано · рамка 1.5 px', style: BuilderType.small),
            ),
          ]),
        ),
        _Panel(
          title: '04 / Иконки',
          caption:
              '24 оригинальные SVG-иконки · 24 px · линия 2 px. Без эмодзи.',
          child: Wrap(
            spacing: 12,
            runSpacing: 18,
            children: [
              for (final glyph in BuilderGlyph.values)
                SizedBox(
                  width: 60,
                  child: Column(
                    children: [
                      BuilderIcon(glyph),
                      const SizedBox(height: 8),
                      Text(
                        glyph.name,
                        style: BuilderType.mono.copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ]),
    ),
  ], gap: 20);
}

class _Controls extends StatefulWidget {
  const _Controls();
  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  bool _calendar = true;
  bool _notes = false;
  int _model = 1;
  String _email = 'name@school';
  @override
  Widget build(BuildContext context) => _stack([
    _Panel(
      title: '01 / Кнопки',
      caption:
          'Обычная, нажатая, загрузка и выключенная. Все кнопки выдерживают перенос текста.',
      child: _stack([
        for (final (name, variant) in [
          ('Основная', BuilderButtonVariant.primary),
          ('Вторичная', BuilderButtonVariant.secondary),
          ('Опасная', BuilderButtonVariant.danger),
          ('Текстовая', BuilderButtonVariant.text),
        ])
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: BuilderType.label),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  BuilderButton(
                    label: variant == BuilderButtonVariant.danger
                        ? 'Начать заново'
                        : 'Создать',
                    variant: variant,
                    onPressed: () => _toast(context, 'Пример нажатия · $name'),
                  ),
                  BuilderButton(
                    label: 'Нажата',
                    variant: variant,
                    previewPressed: true,
                    onPressed: () =>
                        _toast(context, 'Пример нажатого состояния'),
                  ),
                  BuilderButton(
                    label: 'Загрузка',
                    variant: variant,
                    loading: true,
                    onPressed: () {},
                  ),
                  BuilderButton(label: 'Выключена', variant: variant),
                ],
              ),
            ],
          ),
        const Divider(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (icon, label) in [
              (BuilderGlyph.back, 'Назад'),
              (BuilderGlyph.settings, 'Настройки'),
              (BuilderGlyph.plus, 'Добавить'),
              (BuilderGlyph.close, 'Закрыть'),
            ])
              BuilderIconButton(
                icon: icon,
                label: label,
                onPressed: () => _toast(context, label),
              ),
            BuilderIconButton(
              icon: BuilderGlyph.send,
              label: 'Отправить',
              send: true,
              onPressed: () => _toast(context, 'Отправить'),
            ),
          ],
        ),
      ]),
    ),
    _Columns(
      left: _stack([
        _Panel(
          title: '02 / Чипы и бейджи',
          caption: 'Нажмите чип, чтобы прочитать, где обрабатываются данные.',
          child: _stack([
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final location in DataLocation.values)
                  BuilderDataChip(location),
              ],
            ),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                BuilderBadge('Рабочая модель', icon: BuilderGlyph.bolt),
                BuilderBadge('Уровень 2'),
                BuilderBadge('Текущий', warning: true),
                BuilderBadge('Закрыто', icon: BuilderGlyph.lock, neutral: true),
              ],
            ),
          ]),
        ),
        _Panel(
          title: '03 / Прогресс',
          child: _stack([
            const Text('Уровни курса · 3 из 5', style: BuilderType.title),
            const BuilderProgress(completed: 3),
            const SizedBox(height: 4),
            const Text('Шаги урока', style: BuilderType.title),
            const BuilderProgress(
              completed: 3,
              labels: ['Идея', 'Практика', 'Под капотом', 'Проверка', 'Итог'],
            ),
          ]),
        ),
        _Panel(
          title: '04 / Переключатели и выбор',
          child: _stack([
            BuilderToggleRow(
              title: 'Календарь на телефоне',
              subtitle: _calendar ? 'Включён' : 'Выключен',
              value: _calendar,
              onChanged: (v) => setState(() => _calendar = v),
            ),
            BuilderToggleRow(
              title: 'Заметки',
              subtitle: _notes ? 'Включены' : 'Выключены',
              value: _notes,
              onChanged: (v) => setState(() => _notes = v),
            ),
            BuilderSegments(
              options: const [(0, 'Мощная'), (1, 'Рабочая'), (2, 'Быстрая')],
              value: _model,
              onChanged: (v) => setState(() => _model = v),
            ),
          ]),
        ),
      ]),
      right: _stack([
        _Panel(
          title: '05 / Поля ввода',
          caption:
              'Подпись, фокус, подсказка, ошибка. Ошибка объясняет, как исправить поле.',
          child: _stack([
            const BuilderField(
              label: 'Имя ассистента',
              initialValue: 'Помощник по математике',
            ),
            const BuilderField(
              label: 'Инструкция',
              initialValue:
                  'Вы — помощник учителя математики 7–8 классов. Объясняйте по шагам.',
              maxLines: 4,
              helper: 'v3 · инструкция перед каждым запросом',
            ),
            BuilderField(
              label: 'Почта',
              initialValue: _email,
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) => setState(() => _email = v),
              error: RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email)
                  ? null
                  : 'Укажите домен после @, например school.kz',
            ),
            const BuilderField(
              label: 'Неактивное поле',
              initialValue: 'Недоступно в этом режиме',
              enabled: false,
            ),
          ]),
        ),
        _Panel(
          title: '06 / Поле сообщения',
          caption:
              '«Отправить» включается только для непустого текста. В каталоге текст никуда не отправляется.',
          child: BuilderComposer(
            onSend: (text) =>
                _toast(context, 'Демо: сообщение введено, отправка отключена'),
          ),
        ),
      ]),
    ),
  ], gap: 20);
}

class _Compositions extends StatefulWidget {
  const _Compositions();
  @override
  State<_Compositions> createState() => _CompositionsState();
}

class _CompositionsState extends State<_Compositions> {
  int _tab = 0;
  int _model = 1;
  int _compare = 1;
  bool _memory = true;
  int _actionKey = 0;
  MessageState _messageState = MessageState.ready;
  void _inspect() => showBuilderSheet(
    context,
    title: 'Под капотом',
    child: const _TraceExample(),
  );
  @override
  Widget build(BuildContext context) => _stack([
    const BuilderNotice(
      title: 'Демонстрационные данные',
      body:
          'Это каталог компонентов. Ответы приведены как примеры, календарь и другие сервисы не подключены.',
    ),
    _Columns(
      left: _stack([
        _Panel(
          title: '01 / Навигация',
          caption:
              'Три вкладки продукта. Каталог показывает активную вкладку без перехода в приложение.',
          child: _stack([
            BuilderAssistantHeader(
              name: 'Помощник по математике',
              subtitle: 'Уровень 4 · версия 5',
              onSettings: () =>
                  _toast(context, 'Пример перехода в настройки ассистента'),
            ),
            Container(
              color: BuilderColors.background,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  BuilderIconButton(
                    icon: BuilderGlyph.back,
                    label: 'Назад',
                    onPressed: () => _toast(context, 'Пример перехода назад'),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Настройки ассистента', style: BuilderType.h3),
                  ),
                ],
              ),
            ),
            BuilderBottomNavigation(
              index: _tab,
              onChanged: (v) => setState(() => _tab = v),
            ),
          ]),
        ),
        _Panel(
          title: '02 / Сообщения',
          child: Container(
            color: BuilderColors.background,
            padding: const EdgeInsets.all(12),
            child: _stack([
              const BuilderMessage(
                text: 'Составьте проверочную на четверг.',
                user: true,
              ),
              BuilderMessage(
                text:
                    'Готово, 4 задания на линейные уравнения. Уровень сложности — для 7 класса.',
                state: _messageState,
                sources: const ['План урока.pdf · раздел «Линейные уравнения»'],
                onInspect: _inspect,
                onRetry: () =>
                    setState(() => _messageState = MessageState.ready),
                onStop: () =>
                    setState(() => _messageState = MessageState.stopped),
              ),
              BuilderSegments(
                options: const [
                  (MessageState.ready, 'Готово'),
                  (MessageState.generating, 'Генерация'),
                  (MessageState.error, 'Ошибка'),
                ],
                value: _messageState,
                onChanged: (v) => setState(() => _messageState = v),
              ),
            ]),
          ),
        ),
        _Panel(
          title: '03 / До и после',
          caption:
              'Один запрос — два результата. Разница объясняется после практики.',
          child: _stack([
            BuilderSegments(
              options: const [(0, 'Без умения'), (1, 'С умением')],
              value: _compare,
              onChanged: (v) => setState(() => _compare = v),
            ),
            Text(
              _compare == 0
                  ? 'Вот общий план урока по математике.'
                  : 'План для 7А: 28 учеников. Начните с повторения линейных уравнений — на прошлом уроке были ошибки со скобками.',
            ),
            BuilderBadge(
              _compare == 0
                  ? 'Память выключена'
                  : 'Использовано: 2 факта о классе',
              icon: BuilderGlyph.memory,
              neutral: _compare == 0,
            ),
          ]),
        ),
        _Panel(
          title: '04 / Подтверждение действия',
          caption:
              'Состояния: ожидание → загрузка → выполнено / ошибка / отменено.',
          child: _stack([
            BuilderActionCard(
              key: ValueKey(_actionKey),
              title: 'Создать событие «Проверочная, 7А»',
              details: 'Четверг, 10:30–11:15\nКалендарь на телефоне',
              onConfirm: () async {
                await Future<void>.delayed(const Duration(milliseconds: 600));
              },
              onEdit: () => showBuilderSheet(
                context,
                title: 'Пример изменения события',
                child: const BuilderField(
                  label: 'Название',
                  initialValue: 'Проверочная, 7А',
                ),
              ),
            ),
            const Text(
              'Демонстрация: события не создаются.',
              style: BuilderType.small,
            ),
            BuilderButton(
              label: 'Повторить пример',
              variant: BuilderButtonVariant.text,
              icon: BuilderGlyph.reset,
              onPressed: () => setState(() => _actionKey++),
            ),
          ]),
        ),
      ]),
      right: _stack([
        _Panel(
          title: '05 / Карточки уровня',
          child: Container(
            color: BuilderColors.background,
            padding: const EdgeInsets.all(12),
            child: _stack([
              BuilderLessonCard(
                level: 2,
                title: 'Инструкции',
                description: 'Роль, тон, формат',
                status: LessonStatus.completed,
                onPressed: () => _toast(context, 'Пример: повтор уровня 2'),
              ),
              BuilderLessonCard(
                level: 4,
                title: 'Память',
                description: 'Факты о вашем классе',
                status: LessonStatus.current,
                onPressed: () =>
                    _toast(context, 'Пример: продолжение уровня 4'),
              ),
              const BuilderLessonCard(
                level: 5,
                title: 'Инструменты',
                description: 'Календарь, заметки, MCP',
                status: LessonStatus.locked,
              ),
              const BuilderLessonCard(
                level: 6,
                title: 'Голос',
                description: 'Речь → текст → ответ',
                status: LessonStatus.comingSoon,
              ),
            ]),
          ),
        ),
        _Panel(
          title: '06 / Умения',
          child: _stack([
            BuilderSkillCard(
              title: 'Память',
              subtitle: 'В классе 28 учеников',
              icon: BuilderGlyph.memory,
              status: _memory ? SkillStatus.enabled : SkillStatus.disabled,
              level: 4,
              onChanged: (v) => setState(() => _memory = v),
            ),
            const BuilderSkillCard(
              title: 'Инструменты',
              subtitle: 'Календарь и заметки',
              icon: BuilderGlyph.tool,
              status: SkillStatus.locked,
              level: 5,
            ),
            const BuilderSkillCard(
              title: 'Зрение',
              subtitle: 'Работа с фото',
              icon: BuilderGlyph.search,
              status: SkillStatus.comingSoon,
              level: 7,
            ),
            const BuilderSkillCard(
              title: 'Календарь',
              subtitle: 'Нет разрешения ОС',
              icon: BuilderGlyph.calendar,
              status: SkillStatus.unavailable,
              level: 5,
            ),
          ]),
        ),
        _Panel(
          title: '07 / Модель и строка-ссылка',
          child: _stack([
            BuilderSegments(
              options: const [(0, 'Мощная'), (1, 'Рабочая'), (2, 'Быстрая')],
              value: _model,
              onChanged: (v) => setState(() => _model = v),
            ),
            BuilderModelCard(
              title: ['Мощная', 'Рабочая', 'Быстрая'][_model],
              description: [
                'Сложные задачи и подробные объяснения',
                'Повседневные задачи учителя',
                'Короткие ответы и простые задачи',
              ][_model],
              scores: const [
                [5, 2, 5],
                [4, 4, 3],
                [3, 5, 1],
              ][_model],
              selected: true,
              onTap: () => _toast(
                context,
                'Выбрана ${['мощная', 'рабочая', 'быстрая'][_model]} модель · пример',
              ),
            ),
            BuilderLinkRow(
              title: 'Модель',
              subtitle: 'Рабочая · для повседневных задач',
              icon: BuilderGlyph.bolt,
              onTap: () => _toast(context, 'Пример перехода к выбору модели'),
            ),
          ]),
        ),
      ]),
    ),
    _Panel(
      title: '08 / Системные состояния',
      child: _Columns(
        left: _stack([
          const BuilderNotice(
            title: 'Сравните ответы до и после.',
            body: 'Включите память и повторите тот же запрос.',
          ),
          const BuilderNotice(
            title: 'Не отправляйте данные учеников.',
            body: 'Уберите имена, оценки, ИИН и телефоны перед загрузкой.',
            warning: true,
          ),
          BuilderNotice(
            title: 'Нет интернета',
            body: 'Курс и версии доступны. Для разговора нужно подключение.',
            warning: true,
            action: BuilderButton(
              label: 'Повторить',
              variant: BuilderButtonVariant.secondary,
              onPressed: () =>
                  _toast(context, 'Демонстрация повторного подключения'),
            ),
          ),
          const BuilderSkeleton(),
        ]),
        right: _stack([
          const BuilderEmptyState(
            title: 'Память пока пуста',
            body:
                'Ассистент запомнит факты о классе, когда вы пройдёте уровень 4.',
          ),
          BuilderNotice(
            title: 'Не удалось загрузить документ',
            warning: true,
            action: BuilderButton(
              label: 'Попробовать ещё раз',
              variant: BuilderButtonVariant.secondary,
              onPressed: () =>
                  _toast(context, 'Демонстрация повторной загрузки'),
            ),
          ),
          BuilderButton(
            label: 'Показать уведомление',
            icon: BuilderGlyph.check,
            variant: BuilderButtonVariant.secondary,
            onPressed: () => _toast(context, 'Демо: сохранено как версия 6'),
          ),
        ]),
      ),
    ),
  ], gap: 20);
}

class _TraceExample extends StatefulWidget {
  const _TraceExample();
  @override
  State<_TraceExample> createState() => _TraceExampleState();
}

class _TraceExampleState extends State<_TraceExample> {
  int _index = 0;
  @override
  Widget build(BuildContext context) => _stack([
    const BuilderBadge('Пример учебного слоя', icon: BuilderGlyph.code),
    BuilderSegments(
      options: const [(0, 'Схема'), (1, 'Рентген'), (2, 'Аналогия')],
      value: _index,
      onChanged: (v) => setState(() => _index = v),
    ),
    if (_index == 0) ...[
      const Text('Как получен ответ', style: BuilderType.h3),
      for (final (icon, title, subtitle) in [
        (
          BuilderGlyph.doc,
          '1 · Ваш запрос',
          'Составьте проверочную на четверг.',
        ),
        (
          BuilderGlyph.settings,
          '2 · Инструкция v3',
          'Роль и формат ответа учителю.',
        ),
        (BuilderGlyph.memory, '3 · Память', '28 учеников · 7 класс'),
        (
          BuilderGlyph.cloud,
          '4 · Облачная модель',
          'Создаёт ответ из полученного контекста.',
        ),
      ])
        BuilderLinkRow(
          title: title,
          subtitle: subtitle,
          icon: icon,
          onTap: () {},
        ),
      const BuilderDataChip(DataLocation.cloud),
    ] else if (_index == 1) ...[
      const Text('Что увидела модель', style: BuilderType.h3),
      const SelectableText(
        'system:\nВы — помощник учителя математики.\n\nmemory:\nКласс: 7А. Учеников: 28.\n\nuser:\nСоставьте проверочную на четверг.',
        style: BuilderType.mono,
      ),
    ] else
      const Text(
        'Как подготовка к уроку: инструкция задаёт правила, память напоминает о классе, а модель составляет текст. Это система обработки текста, а не человек.',
      ),
  ]);
}

class _Characters extends StatefulWidget {
  const _Characters();
  @override
  State<_Characters> createState() => _CharactersState();
}

class _CharactersState extends State<_Characters> {
  int _level = 4;
  CharacterMood _mood = CharacterMood.idle;
  bool _memoryDisabled = false;
  @override
  Widget build(BuildContext context) => _stack([
    _Columns(
      left: _Panel(
        title: '01 / Соберите ассистента',
        caption: 'Исходный вектор из Char.dc.html. Уровни добавляют модули.',
        child: _stack([
          Center(
            child: BuilderCharacter(
              level: _level,
              size: 220,
              mood: _mood,
              disabledModules: _memoryDisabled ? {4} : {},
            ),
          ),
          Center(
            child: BuilderBadge(
              'Уровень $_level из 5 · ИИ',
              icon: BuilderGlyph.robot,
            ),
          ),
          Slider(
            value: _level.toDouble(),
            min: 0,
            max: 5,
            divisions: 5,
            label: 'Уровень $_level',
            semanticFormatterCallback: (v) => 'Уровень ${v.toInt()} из 5',
            onChanged: (v) => setState(() => _level = v.toInt()),
          ),
          Text(
            [
              'Пустой ассистент',
              'Имя · антенна',
              'Инструкции · датчик',
              'Знания · книга',
              'Память · плашка',
              'Инструменты · ноги',
            ][_level],
            textAlign: TextAlign.center,
            style: BuilderType.title,
          ),
          BuilderToggleRow(
            title: 'Модуль памяти выключен',
            subtitle: 'Выключенный модуль тусклый. Доступен с уровня 4.',
            value: _memoryDisabled,
            onChanged: _level >= 4
                ? (v) => setState(() => _memoryDisabled = v)
                : null,
          ),
        ]),
      ),
      right: _Panel(
        title: '02 / Состояние',
        caption:
            'Состояние подписано и обозначено иконкой. Персонаж не изображает человеческие эмоции.',
        child: _stack([
          for (final mood in CharacterMood.values)
            Semantics(
              selected: _mood == mood,
              child: BuilderCard(
                selected: _mood == mood,
                onTap: () => setState(() => _mood = mood),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    BuilderIcon(mood.glyph, color: BuilderColors.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(mood.label, style: BuilderType.title)),
                    if (_mood == mood)
                      const BuilderIcon(
                        BuilderGlyph.check,
                        color: BuilderColors.primary,
                      ),
                  ],
                ),
              ),
            ),
        ], gap: 8),
      ),
    ),
    _Panel(
      title: '03 / От базовой формы до инструментов',
      caption:
          'Неоткрытые модули видны силуэтом на 14%, как в UK4. Открытый, но выключенный модуль — на 35%.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = constraints.maxWidth >= 780
              ? 6
              : constraints.maxWidth >= 460
              ? 3
              : 2;
          final width = (constraints.maxWidth - (count - 1) * 12) / count;
          return Wrap(
            spacing: 12,
            runSpacing: 20,
            children: [
              for (var level = 0; level <= 5; level++)
                SizedBox(
                  width: width,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: BuilderColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        BuilderCharacter(level: level, size: width - 16),
                        const SizedBox(height: 8),
                        Text(
                          [
                            'База',
                            'Имя',
                            'Инструкции',
                            'Знания',
                            'Память',
                            'Инструменты',
                          ][level],
                          style: BuilderType.small,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
    _Panel(
      title: '04 / Размеры',
      caption:
          '32 и 48 px — компактная голова для шапок и сообщений. 120 px и больше — весь персонаж.',
      child: Wrap(
        spacing: 28,
        runSpacing: 20,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          for (final size in [32.0, 48.0, 120.0, 180.0])
            Column(
              children: [
                BuilderCharacter(level: 5, size: size, compact: size <= 48),
                const SizedBox(height: 12),
                Text('${size.toInt()} px', style: BuilderType.mono),
              ],
            ),
        ],
      ),
    ),
    const BuilderNotice(
      title: 'Без обязательной анимации',
      body:
          'Все состояния читаются статично. При системной настройке «Уменьшить движение» индикаторы загрузки также переходят в статичный вид.',
    ),
  ], gap: 20);
}
