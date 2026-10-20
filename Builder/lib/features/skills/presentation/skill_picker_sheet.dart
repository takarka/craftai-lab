import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui_kit/ui_kit.dart';
import '../domain/skill_scenario.dart';
import '../skills_providers.dart';

typedef PickedSkill = ({SkillScenario skill, Map<String, String> inputs});

/// Lets the user pick a saved skill and fill its inputs from inside the chat.
/// Returns null when dismissed; nothing is sent from here.
Future<PickedSkill?> showSkillPickerSheet(
  BuildContext context, {
  required String ownerId,
  required VoidCallback onOpenSkills,
}) {
  final kk = Localizations.localeOf(context).languageCode == 'kk';
  return showBuilderSheet<PickedSkill>(
    context,
    title: kk ? 'Дағдылар' : 'Навыки',
    child: _SkillPicker(ownerId: ownerId, onOpenSkills: onOpenSkills),
  );
}

class _SkillPicker extends ConsumerStatefulWidget {
  const _SkillPicker({required this.ownerId, required this.onOpenSkills});
  final String ownerId;
  final VoidCallback onOpenSkills;
  @override
  ConsumerState<_SkillPicker> createState() => _SkillPickerState();
}

class _SkillPickerState extends ConsumerState<_SkillPicker> {
  final _form = GlobalKey<FormState>();
  SkillScenario? _selected;
  Map<String, TextEditingController> _inputs = {};

  @override
  void dispose() {
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _select(SkillScenario skill) {
    if (skill.requiredInputs.isEmpty) {
      Navigator.pop<PickedSkill>(context, (skill: skill, inputs: const {}));
      return;
    }
    setState(() {
      _selected = skill;
      _inputs = {
        for (final k in skill.requiredInputs) k: TextEditingController(),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final kk = Localizations.localeOf(context).languageCode == 'kk';
    String t(String ru, String kz) => kk ? kz : ru;
    final selected = _selected;
    if (selected != null) {
      return Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(selected.name, style: BuilderType.h3),
            const SizedBox(height: 4),
            Text(selected.purpose, style: BuilderType.small),
            const SizedBox(height: 16),
            for (final entry in _inputs.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: BuilderField(
                  fieldKey: Key('skillPicker.input.${entry.key}'),
                  controller: entry.value,
                  label: entry.key,
                  minLines: 1,
                  maxLines: 6,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? t('Укажите эти данные', 'Осы деректерді енгізіңіз')
                      : null,
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: BuilderButton(
                    label: t('Назад', 'Артқа'),
                    variant: BuilderButtonVariant.secondary,
                    onPressed: () => setState(() => _selected = null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: BuilderButton(
                    key: const Key('skillPicker.continue'),
                    label: t('Продолжить', 'Жалғастыру'),
                    onPressed: () {
                      if (!_form.currentState!.validate()) return;
                      Navigator.pop<PickedSkill>(context, (
                        skill: selected,
                        inputs: {
                          for (final e in _inputs.entries)
                            e.key: e.value.text.trim(),
                        },
                      ));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final skills = ref.watch(skillsListProvider(widget.ownerId));
    return skills.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => BuilderButton(
        label: t('Повторить загрузку', 'Қайта жүктеу'),
        variant: BuilderButtonVariant.secondary,
        onPressed: () => ref.invalidate(skillsListProvider(widget.ownerId)),
      ),
      data: (items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isEmpty)
            BuilderEmptyState(
              title: t('Навыков пока нет', 'Дағдылар әзірге жоқ'),
              body: t(
                'Создайте навык один раз — и запускайте его прямо из чата.',
                'Дағдыны бір рет жасаңыз — оны тікелей чаттан іске қосыңыз.',
              ),
            )
          else ...[
            Text(
              t(
                'Выберите навык — он подготовит запрос, а отправите его вы.',
                'Дағдыны таңдаңыз — ол сұрау дайындайды, оны өзіңіз жібересіз.',
              ),
              style: BuilderType.small,
            ),
            const SizedBox(height: 12),
            for (final skill in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BuilderLinkRow(
                  key: Key('skillPicker.${skill.id}'),
                  title: skill.name,
                  subtitle: skill.purpose,
                  icon: BuilderGlyph.bolt,
                  onTap: () => _select(skill),
                ),
              ),
          ],
          const SizedBox(height: 4),
          BuilderButton(
            key: const Key('skillPicker.manage'),
            label: items.isEmpty
                ? t('Создать навык', 'Дағды жасау')
                : t('Управлять навыками', 'Дағдыларды басқару'),
            variant: items.isEmpty
                ? BuilderButtonVariant.primary
                : BuilderButtonVariant.text,
            onPressed: () {
              Navigator.pop(context);
              widget.onOpenSkills();
            },
          ),
        ],
      ),
    );
  }
}
