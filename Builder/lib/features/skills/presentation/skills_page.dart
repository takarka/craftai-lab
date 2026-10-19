import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../assistant/presentation/assistant_chat_page.dart';
import '../domain/skill_scenario.dart';
import '../domain/skill_templates.dart';
import '../skills_providers.dart';

bool _kk(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'kk';

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
      appBar: AppBar(title: Text(kk ? 'Дағдылар' : 'Навыки')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('skills.add'),
        onPressed: () => edit(null),
        icon: const Icon(Icons.add),
        label: Text(kk ? 'Қосу' : 'Добавить'),
      ),
      body: skills.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(skillsListProvider(ownerId)),
            child: Text(kk ? 'Қайта жүктеу' : 'Повторить загрузку'),
          ),
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Text(
              kk
                  ? 'Қайталанатын тапсырманың қадамдарын сақтаңыз. Дағды жалпы нұсқауларды және құралдарға рұқсаттарды өзгертпейді.'
                  : 'Сохраните шаги повторяемой задачи. Навык сохраняет общие инструкции и разрешения инструментов.',
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Text(
                kk
                    ? 'Әзірге дағдылар жоқ. Үлгіні таңдаңыз немесе өзіңіз жасаңыз.'
                    : 'Навыков пока нет. Выберите шаблон или создайте свой.',
              ),
            for (final skill in items)
              Card(
                child: ListTile(
                  title: Text(skill.name),
                  subtitle: Text(skill.purpose),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SkillDetailsPage(ownerId: ownerId, skill: skill),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              kk ? 'Үлгілер' : 'Шаблоны',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final template in SkillTemplates.forLocale(isKk: kk))
              ListTile(
                title: Text(template.name),
                subtitle: Text(template.purpose),
                trailing: const Icon(Icons.add),
                onTap: () => edit(template, template: true),
              ),
          ],
        ),
      ),
    );
  }
}

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
  final _form = GlobalKey<FormState>();
  late final List<TextEditingController> _fields;
  late final String _id;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.skill;
    _id = s != null && !widget.fromTemplate
        ? s.id
        : 'skill-${DateTime.now().microsecondsSinceEpoch}';
    _fields = [
      s?.name ?? '',
      s?.purpose ?? '',
      s?.requiredInputs.join('\n') ?? '',
      s?.steps.join('\n') ?? '',
      s?.outputFormat ?? '',
      s?.constraints.join('\n') ?? '',
      s?.sources.join('\n') ?? '',
      s?.qualityCriteria.join('\n') ?? '',
    ].map((text) => TextEditingController(text: text)).toList();
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  List<String> _lines(int index) => _fields[index].text
      .split('\n')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final skill = SkillScenario(
        id: _id,
        name: _fields[0].text.trim(),
        purpose: _fields[1].text.trim(),
        requiredInputs: _lines(2),
        steps: _lines(3),
        outputFormat: _fields[4].text.trim(),
        constraints: _lines(5),
        sources: _lines(6),
        qualityCriteria: _lines(7),
        revision: widget.fromTemplate ? 1 : widget.skill?.revision ?? 1,
      );
      skill.validate();
      await ref.read(skillsControllerProvider(widget.ownerId)).save(skill);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = _kk(context)
              ? 'Сақталмады. Өрістерді тексеріңіз. Дағды басқа жерде өзгерсе, оны тізімнен қайта ашыңыз.'
              : 'Не удалось сохранить. Проверьте поля. Если навык изменён в другом окне, откройте его заново из списка.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kk = _kk(context);
    final labels = kk
        ? [
            'Атауы',
            'Мақсаты',
            'Міндетті деректер',
            'Қадамдар',
            'Нәтиже пішімі',
            'Шектеулер',
            'Дереккөздер',
            'Сапа өлшемдері',
          ]
        : [
            'Название',
            'Назначение',
            'Обязательные входы',
            'Шаги',
            'Формат результата',
            'Ограничения',
            'Источники',
            'Критерии качества',
          ];
    return Scaffold(
      appBar: AppBar(title: Text(kk ? 'Дағдыны өңдеу' : 'Редактор навыка')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (var i = 0; i < labels.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextFormField(
                  key: Key('skill.field.$i'),
                  controller: _fields[i],
                  enabled: !_saving,
                  minLines: i == 0 ? 1 : 2,
                  maxLines: i == 0 ? 1 : 6,
                  maxLength: i == 0 ? 120 : null,
                  decoration: InputDecoration(
                    labelText: labels[i],
                    helperText: [2, 3, 5, 6, 7].contains(i)
                        ? (kk
                              ? 'Әр тармақ — жаңа жолда'
                              : 'Каждый пункт — с новой строки')
                        : null,
                  ),
                  validator: (value) {
                    if ([0, 1, 3, 4, 7].contains(i) &&
                        (value ?? '').trim().isEmpty) {
                      return kk ? 'Өрісті толтырыңыз' : 'Заполните поле';
                    }
                    if (i == 2 &&
                        _lines(2).toSet().length != _lines(2).length) {
                      return kk
                          ? 'Атаулар қайталанбауы керек'
                          : 'Названия входов должны различаться';
                    }
                    return null;
                  },
                ),
              ),
            Text(
              kk
                  ? 'Дереккөз атауы оның мазмұнын ашпайды. Қажетті мәтінді іске қосу кезінде кіріс деректерге қосыңыз.'
                  : 'Название источника не загружает его содержимое. Нужный текст добавьте во входные данные при запуске.',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!),
              ),
            FilledButton(
              key: const Key('skill.save'),
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? (kk ? 'Сақталуда…' : 'Сохранение…')
                    : (kk ? 'Сақтау' : 'Сохранить'),
              ),
            ),
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

  @override
  Widget build(BuildContext context) {
    final kk = _kk(context);
    final skill = widget.skill;
    return Scaffold(
      appBar: AppBar(
        title: Text(skill.name),
        actions: [
          IconButton(
            tooltip: kk ? 'Өңдеу' : 'Редактировать',
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
            tooltip: kk ? 'Жою' : 'Удалить',
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleting
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(
                          kk ? 'Дағдыны жою керек пе?' : 'Удалить навык?',
                        ),
                        content: Text(skill.name),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(kk ? 'Бас тарту' : 'Отмена'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(kk ? 'Жою' : 'Удалить'),
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
                              kk
                                  ? 'Жойылмады. Қайталап көріңіз.'
                                  : 'Не удалось удалить. Попробуйте ещё раз.',
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
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(skill.purpose),
            const SizedBox(height: 16),
            Text(
              kk ? 'Сценарий' : 'Сценарий',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (var i = 0; i < skill.steps.length; i++)
              Text('${i + 1}. ${skill.steps[i]}'),
            const SizedBox(height: 12),
            Text('${kk ? 'Нәтиже' : 'Результат'}: ${skill.outputFormat}'),
            if (skill.constraints.isNotEmpty)
              Text(
                '${kk ? 'Шектеулер' : 'Ограничения'}: ${skill.constraints.join('; ')}',
              ),
            Text(
              '${kk ? 'Сапа өлшемдері' : 'Критерии качества'}: ${skill.qualityCriteria.join('; ')}',
            ),
            const SizedBox(height: 12),
            Text(
              '${kk ? 'Мәлімделген дереккөздер' : 'Заявленные источники'}: ${skill.sources.isEmpty ? (kk ? 'жоқ' : 'нет') : skill.sources.join('; ')}',
            ),
            Text(
              kk
                  ? 'Дереккөздер автоматты түрде ашылмайды. Қажетті мәтінді төменде беріңіз.'
                  : 'Источники автоматически не открываются. Передайте нужный текст ниже.',
            ),
            for (final entry in _inputs.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: TextFormField(
                  controller: entry.value,
                  minLines: 2,
                  maxLines: 8,
                  decoration: InputDecoration(labelText: entry.key),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? (kk ? 'Осы деректерді енгізіңіз' : 'Укажите эти данные')
                      : null,
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('skill.prepare'),
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
              child: Text(kk ? 'Чатта тексеру' : 'Проверить в чате'),
            ),
          ],
        ),
      ),
    );
  }
}
