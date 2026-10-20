import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui_kit/ui_kit.dart';
import '../../assistant/presentation/assistant_chat_page.dart';
import '../domain/skill_scenario.dart';
import '../domain/skill_templates.dart';
import '../skills_providers.dart';

bool _kk(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'kk';

String _t(bool kk, String ru, String kz) => kk ? kz : ru;

class SkillsPage extends ConsumerWidget {
  const SkillsPage({super.key, required this.ownerId});
  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kk = _kk(context);
    final skills = ref.watch(skillsListProvider(ownerId));
    void edit(SkillScenario? skill, {bool template = false}) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SkillEditorPage(
            ownerId: ownerId,
            skill: skill,
            fromTemplate: template,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t(kk, 'Навыки', 'Дағдылар'),
          style: BuilderTypography.titleMedium,
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: BuilderButton(
            key: const Key('skills.add'),
            label: _t(kk, 'Создать навык', 'Дағды жасау'),
            icon: BuilderGlyph.plus,
            onPressed: () => edit(null),
          ),
        ),
      ),
      body: skills.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: BuilderButton(
            label: _t(kk, 'Повторить загрузку', 'Қайта жүктеу'),
            variant: BuilderButtonVariant.secondary,
            onPressed: () => ref.invalidate(skillsListProvider(ownerId)),
          ),
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            BuilderNotice(
              title: _t(
                kk,
                'Навык — это готовая инструкция',
                'Дағды — дайын нұсқаулық',
              ),
              body: _t(
                kk,
                'Вы один раз описываете повторяющуюся задачу, а потом запускаете её в чате за пару нажатий. Навык не получает доступ к инструментам и файлам.',
                'Қайталанатын тапсырманы бір рет сипаттайсыз, содан кейін чатта бірнеше басумен іске қосасыз. Дағды құралдарға мен файлдарға қол жеткізбейді.',
              ),
            ),
            const SizedBox(height: 20),
            if (items.isNotEmpty) ...[
              Text(
                _t(kk, 'Мои навыки', 'Менің дағдыларым'),
                style: BuilderType.h3,
              ),
              const SizedBox(height: 12),
              for (final skill in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BuilderLinkRow(
                    title: skill.name,
                    subtitle: skill.purpose,
                    icon: BuilderGlyph.bolt,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            SkillDetailsPage(ownerId: ownerId, skill: skill),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            Text(
              items.isEmpty
                  ? _t(
                      kk,
                      'Начните с готового шаблона',
                      'Дайын үлгіден бастаңыз',
                    )
                  : _t(kk, 'Шаблоны', 'Үлгілер'),
              style: BuilderType.h3,
            ),
            const SizedBox(height: 4),
            Text(
              _t(
                kk,
                'Выберите шаблон — его можно сразу сохранить или подправить.',
                'Үлгіні таңдаңыз — оны бірден сақтауға немесе түзетуге болады.',
              ),
              style: BuilderType.small,
            ),
            const SizedBox(height: 12),
            for (final template in SkillTemplates.forLocale(isKk: kk))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BuilderLinkRow(
                  title: template.name,
                  subtitle: template.purpose,
                  icon: BuilderGlyph.plus,
                  onTap: () => edit(template, template: true),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Guided three-step editor. Existing skills and templates open on the
/// review step so they can be saved immediately or adjusted per section.
class SkillEditorPage extends ConsumerStatefulWidget {
  const SkillEditorPage({
    super.key,
    required this.ownerId,
    this.skill,
    this.fromTemplate = false,
  });
  final String ownerId;
  final SkillScenario? skill;
  final bool fromTemplate;
  @override
  ConsumerState<SkillEditorPage> createState() => _SkillEditorPageState();
}

class _SkillEditorPageState extends ConsumerState<SkillEditorPage> {
  static const _reviewStep = 3;
  final _form = GlobalKey<FormState>();
  late final String _id;
  late final TextEditingController _name;
  late final TextEditingController _purpose;
  late final TextEditingController _inputDraft;
  late final TextEditingController _output;
  late final TextEditingController _constraints;
  late final TextEditingController _sources;
  late final TextEditingController _quality;
  late final List<TextEditingController> _steps;
  late final List<String> _inputs;
  late int _step;
  bool _saving = false;
  String? _error;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    final s = widget.skill;
    _id = s != null && !widget.fromTemplate
        ? s.id
        : 'skill-${DateTime.now().microsecondsSinceEpoch}';
    _name = TextEditingController(text: s?.name ?? '');
    _purpose = TextEditingController(text: s?.purpose ?? '');
    _inputDraft = TextEditingController();
    _output = TextEditingController(text: s?.outputFormat ?? '');
    _constraints = TextEditingController(text: s?.constraints.join('\n') ?? '');
    _sources = TextEditingController(text: s?.sources.join('\n') ?? '');
    _quality = TextEditingController(text: s?.qualityCriteria.join('\n') ?? '');
    _steps = [
      for (final step in s?.steps ?? <String>[''])
        TextEditingController(text: step),
    ];
    _inputs = [...?s?.requiredInputs];
    _step = s == null ? 0 : _reviewStep;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _purpose,
      _inputDraft,
      _output,
      _constraints,
      _sources,
      _quality,
      ..._steps,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _lines(TextEditingController c) => c.text
      .split('\n')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();

  List<String> get _stepTexts => [
    for (final c in _steps)
      if (c.text.trim().isNotEmpty) c.text.trim(),
  ];

  String _suggestName() {
    final text = _purpose.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.length <= 40) return text;
    final cut = text.substring(0, 40);
    final space = cut.lastIndexOf(' ');
    return (space > 15 ? cut.substring(0, space) : cut).trim();
  }

  void _addInput(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return;
    final kk = _kk(context);
    setState(() {
      if (_inputs.contains(value)) {
        _inputError = _t(
          kk,
          'Названия входов должны различаться',
          'Атаулар қайталанбауы керек',
        );
        return;
      }
      _inputError = null;
      _inputs.add(value);
      _inputDraft.clear();
    });
  }

  void _goTo(int step) => setState(() {
    _error = null;
    _step = step;
  });

  void _next() {
    if (!_form.currentState!.validate()) return;
    if (_step == 0 && _name.text.trim().isEmpty) {
      _name.text = _suggestName();
    }
    _goTo(_step + 1);
  }

  Future<void> _save() async {
    final kk = _kk(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final quality = _lines(_quality);
      final skill = SkillScenario(
        id: _id,
        name: _name.text.trim(),
        purpose: _purpose.text.trim(),
        requiredInputs: List.of(_inputs),
        steps: _stepTexts,
        outputFormat: _output.text.trim(),
        constraints: _lines(_constraints),
        sources: _lines(_sources),
        qualityCriteria: quality.isEmpty
            ? [
                _t(
                  kk,
                  'Результат соответствует назначению и формату',
                  'Нәтиже мақсатқа және пішімге сәйкес',
                ),
              ]
            : quality,
        revision: widget.fromTemplate ? 1 : widget.skill?.revision ?? 1,
      );
      skill.validate();
      await ref.read(skillsControllerProvider(widget.ownerId)).save(skill);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = _t(
            kk,
            'Не удалось сохранить. Проверьте поля. Если навык изменён в другом окне, откройте его заново из списка.',
            'Сақталмады. Өрістерді тексеріңіз. Дағды басқа жерде өзгерсе, оны тізімнен қайта ашыңыз.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) => (value ?? '').trim().isEmpty
      ? _t(_kk(context), 'Заполните поле', 'Өрісті толтырыңыз')
      : null;

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Text(
      text,
      style: BuilderType.body.copyWith(color: BuilderColors.inkSecondary),
    ),
  );

  Widget _stepAbout(bool kk) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_t(kk, 'О чём навык?', 'Дағды не туралы?'), style: BuilderType.h2),
      const SizedBox(height: 8),
      _hint(
        _t(
          kk,
          'Опишите своими словами, с какой задачей он помогает.',
          'Қандай тапсырмаға көмектесетінін өз сөзіңізбен сипаттаңыз.',
        ),
      ),
      BuilderField(
        fieldKey: const Key('skill.field.1'),
        controller: _purpose,
        label: _t(kk, 'Что должен делать навык?', 'Дағды не істеуі керек?'),
        hint: _t(
          kk,
          'Например: составить план урока по теме',
          'Мысалы: тақырып бойынша сабақ жоспарын жасау',
        ),
        minLines: 2,
        maxLines: 5,
        validator: _required,
        enabled: !_saving,
      ),
      const SizedBox(height: 20),
      BuilderField(
        fieldKey: const Key('skill.field.0'),
        controller: _name,
        label: _t(kk, 'Название', 'Атауы'),
        helper: _t(
          kk,
          'Можно оставить пустым — придумаем из описания',
          'Бос қалдыруға болады — сипаттамадан ойлап табамыз',
        ),
        maxLength: 120,
        enabled: !_saving,
      ),
    ],
  );

  Widget _stepInputs(bool kk) {
    final suggestions = kk
        ? ['Тақырып', 'Сынып', 'Ұзақтығы', 'Күн', 'Мәтін']
        : ['Тема', 'Класс', 'Длительность', 'Дата', 'Текст'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t(kk, 'Что вы сообщите при запуске?', 'Іске қосқанда нені айтасыз?'),
          style: BuilderType.h2,
        ),
        const SizedBox(height: 8),
        _hint(
          _t(
            kk,
            'Это то, что навык будет спрашивать у вас каждый раз: тема, класс и так далее. Можно ничего не добавлять.',
            'Дағды сізден әр жолы сұрайтын деректер: тақырып, сынып және т.б. Ештеңе қоспауға да болады.',
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions)
              if (!_inputs.contains(s))
                ActionChip(
                  label: Text('+ $s'),
                  onPressed: _saving ? null : () => _addInput(s),
                ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BuilderField(
                fieldKey: const Key('skill.input.draft'),
                controller: _inputDraft,
                label: _t(kk, 'Свой вариант', 'Өз нұсқаңыз'),
                hint: _t(kk, 'Например: Предмет', 'Мысалы: Пән'),
                error: _inputError,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_inputError != null) setState(() => _inputError = null);
                },
                enabled: !_saving,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 36),
              child: BuilderIconButton(
                icon: BuilderGlyph.plus,
                label: _t(kk, 'Добавить', 'Қосу'),
                onPressed: _saving ? null : () => _addInput(_inputDraft.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_inputs.isEmpty)
          Text(
            _t(kk, 'Пока ничего не выбрано', 'Әзірге ештеңе таңдалмады'),
            style: BuilderType.small,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final input in _inputs)
                InputChip(
                  key: Key('skill.input.$input'),
                  label: Text(input),
                  onDeleted: _saving
                      ? null
                      : () => setState(() => _inputs.remove(input)),
                ),
            ],
          ),
      ],
    );
  }

  Widget _stepResult(bool kk) {
    final presets = kk
        ? {
            'План': 'Нөмірленген жоспар: кезең, уақыт, әрекет',
            'Тізім': 'Қысқа тармақтар тізімі',
            'Кесте': 'Кесте: бағандар мен жолдар',
            'Мәтін': 'Қысқа байланысты мәтін',
          }
        : {
            'План': 'Нумерованный план: этап, время, действие',
            'Список': 'Короткий список пунктов',
            'Таблица': 'Таблица: столбцы и строки',
            'Текст': 'Короткий связный текст',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t(kk, 'Что должно получиться?', 'Не шығуы керек?'),
          style: BuilderType.h2,
        ),
        const SizedBox(height: 8),
        _hint(
          _t(
            kk,
            'Выберите вид ответа и опишите шаги, которые нужно выполнить.',
            'Жауап түрін таңдап, орындалатын қадамдарды сипаттаңыз.',
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in presets.entries)
              ChoiceChip(
                label: Text(e.key),
                selected: _output.text == e.value,
                onSelected: _saving
                    ? null
                    : (_) => setState(() => _output.text = e.value),
              ),
          ],
        ),
        const SizedBox(height: 12),
        BuilderField(
          fieldKey: const Key('skill.field.4'),
          controller: _output,
          label: _t(kk, 'Как оформить ответ', 'Жауапты қалай рәсімдеу'),
          hint: _t(
            kk,
            'Например: этап, время, действие',
            'Мысалы: кезең, уақыт, әрекет',
          ),
          minLines: 2,
          maxLines: 4,
          validator: _required,
          onChanged: (_) => setState(() {}),
          enabled: !_saving,
        ),
        const SizedBox(height: 20),
        Text(_t(kk, 'Шаги', 'Қадамдар'), style: BuilderType.title),
        const SizedBox(height: 8),
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14, right: 8),
                  child: Text('${i + 1}.', style: BuilderType.title),
                ),
                Expanded(
                  child: TextFormField(
                    key: Key('skill.step.$i'),
                    controller: _steps[i],
                    enabled: !_saving,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: _t(
                        kk,
                        'Что сделать на этом шаге',
                        'Бұл қадамда не істеу керек',
                      ),
                    ),
                    validator: i == 0 && _stepTexts.isEmpty ? _required : null,
                  ),
                ),
                if (_steps.length > 1)
                  IconButton(
                    tooltip: _t(kk, 'Убрать шаг', 'Қадамды алып тастау'),
                    icon: const Icon(Icons.close),
                    onPressed: _saving
                        ? null
                        : () => setState(() => _steps.removeAt(i).dispose()),
                  ),
              ],
            ),
          ),
        BuilderButton(
          key: const Key('skill.step.add'),
          label: _t(kk, 'Добавить шаг', 'Қадам қосу'),
          icon: BuilderGlyph.plus,
          variant: BuilderButtonVariant.text,
          onPressed: _saving
              ? null
              : () => setState(() => _steps.add(TextEditingController())),
        ),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('skill.advanced'),
            tilePadding: EdgeInsets.zero,
            title: Text(
              _t(kk, 'Дополнительно', 'Қосымша'),
              style: BuilderType.title,
            ),
            subtitle: Text(
              _t(
                kk,
                'Необязательно: ограничения, источники, критерии',
                'Міндетті емес: шектеулер, дереккөздер, өлшемдер',
              ),
              style: BuilderType.small,
            ),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              BuilderField(
                fieldKey: const Key('skill.field.5'),
                controller: _constraints,
                label: _t(kk, 'Чего не делать', 'Нені істемеу керек'),
                helper: _t(
                  kk,
                  'Каждый пункт — с новой строки',
                  'Әр тармақ — жаңа жолда',
                ),
                minLines: 2,
                maxLines: 5,
                enabled: !_saving,
              ),
              const SizedBox(height: 16),
              BuilderField(
                fieldKey: const Key('skill.field.7'),
                controller: _quality,
                label: _t(
                  kk,
                  'Как понять, что получилось хорошо',
                  'Жақсы шыққанын қалай түсінуге болады',
                ),
                helper: _t(
                  kk,
                  'Если оставить пустым, подставим общий критерий',
                  'Бос қалдырсаңыз, жалпы өлшем қоямыз',
                ),
                minLines: 2,
                maxLines: 5,
                enabled: !_saving,
              ),
              const SizedBox(height: 16),
              BuilderField(
                fieldKey: const Key('skill.field.6'),
                controller: _sources,
                label: _t(kk, 'Названия источников', 'Дереккөздер атаулары'),
                helper: _t(
                  kk,
                  'Название не загружает содержимое: нужный текст добавьте при запуске',
                  'Атау мазмұнды жүктемейді: қажетті мәтінді іске қосқанда қосыңыз',
                ),
                minLines: 2,
                maxLines: 5,
                enabled: !_saving,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String title, List<String> lines, int step, bool kk) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: BuilderCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: BuilderType.title)),
                  TextButton(
                    key: Key('skill.edit.$step'),
                    onPressed: _saving ? null : () => _goTo(step),
                    child: Text(_t(kk, 'Изменить', 'Өзгерту')),
                  ),
                ],
              ),
              if (lines.isEmpty)
                Text('—', style: BuilderType.body)
              else
                for (final line in lines) Text(line, style: BuilderType.body),
            ],
          ),
        ),
      );

  Widget _stepReview(bool kk) {
    final steps = _stepTexts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t(kk, 'Проверьте навык', 'Дағдыны тексеріңіз'),
          style: BuilderType.h2,
        ),
        const SizedBox(height: 8),
        _hint(
          _t(
            kk,
            'Всё верно? Нажмите «Сохранить» или измените нужный раздел.',
            'Бәрі дұрыс па? «Сақтау» түймесін басыңыз немесе қажетті бөлімді өзгертіңіз.',
          ),
        ),
        _section(
          _name.text.trim().isEmpty ? _suggestName() : _name.text.trim(),
          [_purpose.text.trim()],
          0,
          kk,
        ),
        _section(
          _t(kk, 'Вы сообщите при запуске', 'Іске қосқанда айтасыз'),
          _inputs,
          1,
          kk,
        ),
        _section(
          _t(kk, 'Шаги', 'Қадамдар'),
          [for (var i = 0; i < steps.length; i++) '${i + 1}. ${steps[i]}'],
          2,
          kk,
        ),
        _section(_t(kk, 'Ответ', 'Жауап'), [_output.text.trim()], 2, kk),
        BuilderNotice(
          title: _t(kk, 'Навык — это текст', 'Дағды — мәтін'),
          body: _t(
            kk,
            'Он меняет только инструкции для ассистента и не получает доступ к инструментам, файлам или памяти.',
            'Ол көмекшіге арналған нұсқауларды ғана өзгертеді, құралдарға, файлдарға немесе жадқа қол жеткізбейді.',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          BuilderNotice(title: _error!, warning: true),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final kk = _kk(context);
    final isReview = _step == _reviewStep;
    final body = switch (_step) {
      0 => _stepAbout(kk),
      1 => _stepInputs(kk),
      2 => _stepResult(kk),
      _ => _stepReview(kk),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.skill == null || widget.fromTemplate
              ? _t(kk, 'Новый навык', 'Жаңа дағды')
              : _t(kk, 'Редактор навыка', 'Дағдыны өңдеу'),
          style: BuilderTypography.titleMedium,
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              if (_step > 0 && !isReview) ...[
                Expanded(
                  child: BuilderButton(
                    key: const Key('skill.back'),
                    label: _t(kk, 'Назад', 'Артқа'),
                    variant: BuilderButtonVariant.secondary,
                    onPressed: _saving ? null : () => _goTo(_step - 1),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: 2,
                child: isReview
                    ? BuilderButton(
                        key: const Key('skill.save'),
                        label: _t(kk, 'Сохранить', 'Сақтау'),
                        loading: _saving,
                        loadingLabel: _t(kk, 'Сохранение…', 'Сақталуда…'),
                        icon: BuilderGlyph.check,
                        onPressed: _saving ? null : _save,
                      )
                    : BuilderButton(
                        key: const Key('skill.next'),
                        label: _step == 2
                            ? _t(kk, 'Проверить', 'Тексеру')
                            : _t(kk, 'Далее', 'Әрі қарай'),
                        onPressed: _saving ? null : _next,
                      ),
              ),
            ],
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            BuilderProgress(
              completed: _step + 1,
              total: 4,
              labels: kk
                  ? ['Сипаттама', 'Деректер', 'Нәтиже', 'Тексеру']
                  : ['Суть', 'Данные', 'Результат', 'Проверка'],
            ),
            const SizedBox(height: 24),
            body,
          ],
        ),
      ),
    );
  }
}

class SkillDetailsPage extends ConsumerStatefulWidget {
  const SkillDetailsPage({
    super.key,
    required this.ownerId,
    required this.skill,
  });
  final String ownerId;
  final SkillScenario skill;
  @override
  ConsumerState<SkillDetailsPage> createState() => _SkillDetailsPageState();
}

class _SkillDetailsPageState extends ConsumerState<SkillDetailsPage> {
  final _form = GlobalKey<FormState>();
  late final _inputs = {
    for (final key in widget.skill.requiredInputs) key: TextEditingController(),
  };
  bool _deleting = false;
  @override
  void dispose() {
    for (final input in _inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  Widget _detail(String title, List<String> lines) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: BuilderType.label),
        const SizedBox(height: 4),
        for (final line in lines) Text(line, style: BuilderType.body),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final kk = _kk(context);
    final skill = widget.skill;
    return Scaffold(
      appBar: AppBar(
        title: Text(skill.name, style: BuilderTypography.titleMedium),
        actions: [
          IconButton(
            tooltip: _t(kk, 'Редактировать', 'Өңдеу'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: _deleting
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SkillEditorPage(
                          ownerId: widget.ownerId,
                          skill: skill,
                        ),
                      ),
                    );
                    // Reload from the list: this page holds an immutable saved revision.
                    if (context.mounted) Navigator.of(context).pop();
                  },
          ),
          IconButton(
            tooltip: _t(kk, 'Удалить', 'Жою'),
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleting
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(
                          _t(kk, 'Удалить навык?', 'Дағдыны жою керек пе?'),
                        ),
                        content: Text(skill.name),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(_t(kk, 'Отмена', 'Бас тарту')),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(_t(kk, 'Удалить', 'Жою')),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !mounted) return;
                    setState(() => _deleting = true);
                    try {
                      await ref
                          .read(skillsControllerProvider(widget.ownerId))
                          .delete(skill.id);
                      if (context.mounted) Navigator.of(context).pop();
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _t(
                                kk,
                                'Не удалось удалить. Попробуйте ещё раз.',
                                'Жойылмады. Қайталап көріңіз.',
                              ),
                            ),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _deleting = false);
                    }
                  },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: BuilderButton(
            key: const Key('skill.prepare'),
            label: _t(kk, 'Подготовить запуск', 'Іске қосуға дайындау'),
            icon: BuilderGlyph.bolt,
            onPressed: _deleting
                ? null
                : () {
                    if (!_form.currentState!.validate()) return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AssistantChatPage(
                          ownerId: widget.ownerId,
                          skillRun: SkillRunDraft(
                            skill: skill,
                            inputs: {
                              for (final e in _inputs.entries)
                                e.key: e.value.text.trim(),
                            },
                          ),
                        ),
                      ),
                    );
                  },
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            BuilderCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BuilderIconTile(BuilderGlyph.bolt),
                  const SizedBox(width: 12),
                  Expanded(child: Text(skill.purpose, style: BuilderType.body)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_inputs.isNotEmpty) ...[
              Text(
                _t(kk, 'Что нужно указать', 'Нені көрсету керек'),
                style: BuilderType.h3,
              ),
              const SizedBox(height: 12),
              for (final entry in _inputs.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: BuilderField(
                    controller: entry.value,
                    label: entry.key,
                    minLines: 2,
                    maxLines: 8,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? _t(
                            kk,
                            'Укажите эти данные',
                            'Осы деректерді енгізіңіз',
                          )
                        : null,
                  ),
                ),
            ] else
              BuilderNotice(
                title: _t(
                  kk,
                  'Ничего вводить не нужно',
                  'Ештеңе енгізу керек емес',
                ),
                body: _t(
                  kk,
                  'Навык можно запускать сразу.',
                  'Дағдыны бірден іске қосуға болады.',
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _t(
                kk,
                'Дальше вы увидите проверку в чате — ничего не отправится без вашего нажатия «Запустить».',
                'Әрі қарай чатта тексеру көресіз — «Іске қосу» түймесін баспайынша ештеңе жіберілмейді.',
              ),
              style: BuilderType.small,
            ),
            const SizedBox(height: 16),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  _t(kk, 'Как работает навык', 'Дағды қалай жұмыс істейді'),
                  style: BuilderType.title,
                ),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detail(_t(kk, 'Сценарий', 'Сценарий'), [
                    for (var i = 0; i < skill.steps.length; i++)
                      '${i + 1}. ${skill.steps[i]}',
                  ]),
                  _detail(_t(kk, 'Результат', 'Нәтиже'), [skill.outputFormat]),
                  if (skill.constraints.isNotEmpty)
                    _detail(
                      _t(kk, 'Ограничения', 'Шектеулер'),
                      skill.constraints,
                    ),
                  _detail(
                    _t(kk, 'Критерии качества', 'Сапа өлшемдері'),
                    skill.qualityCriteria,
                  ),
                  if (skill.sources.isNotEmpty) ...[
                    _detail(
                      _t(kk, 'Заявленные источники', 'Мәлімделген дереккөздер'),
                      skill.sources,
                    ),
                    Text(
                      _t(
                        kk,
                        'Источники автоматически не открываются. Передайте нужный текст выше.',
                        'Дереккөздер автоматты түрде ашылмайды. Қажетті мәтінді жоғарыда беріңіз.',
                      ),
                      style: BuilderType.small,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
