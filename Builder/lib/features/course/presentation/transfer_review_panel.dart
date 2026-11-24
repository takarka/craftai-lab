import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui_kit/ui_kit.dart';
import '../domain/transfer_review.dart';
import '../transfer_review_providers.dart';
import 'course_strings.dart';

class TransferReviewPanel extends ConsumerStatefulWidget {
  const TransferReviewPanel({
    super.key,
    required this.ownerId,
    required this.defaultPrompt,
    required this.openAgents,
    required this.onPracticeReviewed,
  });

  final String ownerId;
  final String defaultPrompt;
  final VoidCallback openAgents;
  final VoidCallback onPracticeReviewed;

  @override
  ConsumerState<TransferReviewPanel> createState() =>
      _TransferReviewPanelState();
}

class _TransferReviewPanelState extends ConsumerState<TransferReviewPanel> {
  final _first = TextEditingController();
  final _instruction = TextEditingController();
  final _second = TextEditingController();

  bool _saving = false;
  bool _saveFailed = false;

  @override
  void dispose() {
    _first.dispose();
    _instruction.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _save(
    TransferReview Function(TransferReview) update, {
    Future<void> Function(TransferReview)? then,
  }) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final provider = transferReviewProvider(widget.ownerId);
    try {
      await ref.read(provider.notifier).change(
        (current) => update(current ?? TransferReview(prompt: widget.defaultPrompt)),
      );
      if (!mounted) return;
      final saved = ref.read(provider).asData?.value;
      if (saved != null) {
        if (saved.secondReviewed) widget.onPracticeReviewed();
        if (then != null) await then(saved);
      }
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _criterion(CourseStrings cs, TransferCriterion criterion) =>
      switch (criterion) {
        TransferCriterion.source =>
          cs.t('Верность источнику', 'Дереккөзге сәйкестік'),
        TransferCriterion.accuracy =>
          cs.t('Фактическая точность', 'Деректердің дәлдігі'),
        TransferCriterion.grade => cs.t('Уровень класса', 'Сынып деңгейі'),
        TransferCriterion.format => cs.t('Формат задания', 'Тапсырма пішімі'),
      };

  String _verdict(CourseStrings cs, TransferVerdict verdict) => switch (verdict) {
    TransferVerdict.met => cs.t('Выполнено', 'Орындалды'),
    TransferVerdict.revise => cs.t('Нужно исправить', 'Түзету керек'),
  };

  String _result(CourseStrings cs, TransferChange change) => switch (change) {
    TransferChange.improved =>
      cs.t('Отмечено улучшение.', 'Жақсару белгіленді.'),
    TransferChange.worse =>
      cs.t('Некоторые оценки стали хуже.', 'Кейбір бағалар төмендеді.'),
    TransferChange.mixed =>
      cs.t('Есть улучшения и ухудшения.', 'Жақсарғаны да, нашарлағаны да бар.'),
    TransferChange.unchanged =>
      cs.t('Оценки не изменились.', 'Бағалар өзгерген жоқ.'),
  };

  Widget _capture({
    required String id,
    required String label,
    required TextEditingController controller,
    required CourseStrings cs,
    required ValueChanged<String> save,
    int maxLength = 2500,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BuilderField(
          fieldKey: Key('transfer.$id.input'),
          label: label,
          controller: controller,
          enabled: !_saving,
          maxLines: 4,
          maxLength: maxLength,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        BuilderButton(
          key: Key('transfer.$id.save'),
          label: cs.t('Сохранить', 'Сақтау'),
          onPressed: _saving || controller.text.trim().isEmpty
              ? null
              : () => save(controller.text.trim()),
        ),
      ],
    );
  }

  Widget _answer(String id, String title, String value) => BuilderCard(
    key: Key('transfer.$id.saved'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: BuilderType.title),
        const SizedBox(height: 8),
        SelectableText(value, style: BuilderType.body),
      ],
    ),
  );

  Widget _checklist(
    CourseStrings cs,
    TransferReview review, {
    required bool second,
  }) {
    final round = second ? 'repeat' : 'first';
    final marks = second ? review.second : review.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cs.t('Ваша оценка ответа', 'Жауапқа берген бағаңыз'),
          style: BuilderType.title,
        ),
        const SizedBox(height: 8),
        for (final criterion in TransferCriterion.values) ...[
          Text(_criterion(cs, criterion), style: BuilderType.body),
          Wrap(
            spacing: 8,
            children: [
              for (final verdict in TransferVerdict.values)
                ChoiceChip(
                  key: Key('transfer.$round.${criterion.name}.${verdict.name}'),
                  label: Text(_verdict(cs, verdict)),
                  selected: marks[criterion] == verdict,
                  onSelected: _saving || (!second && review.instructionChange.isNotEmpty)
                      ? null
                      : (_) => _save(
                          (current) {
                            final values = {
                              ...(second ? current.second : current.first),
                              criterion: verdict,
                            };
                            return second
                                ? current.copyWith(second: values)
                                : current.copyWith(first: values);
                          },
                        ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _content(CourseStrings cs, TransferReview? saved) {
    final review = saved ?? TransferReview(prompt: widget.defaultPrompt);
    final firstTitle = cs.t('Исходный ответ', 'Бастапқы жауап');
    final editTitle = cs.t('Одно изменение инструкции', 'Нұсқаулықтағы бір өзгеріс');
    final secondTitle = cs.t('Повторный ответ', 'Қайта алынған жауап');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(cs.t('Проверить ответ', 'Жауапты тексеру'), style: BuilderType.h2),
        const SizedBox(height: 8),
        Text(
          cs.t(
            'Возьмите только учебный пример. Не вставляйте данные учеников. Ответы и оценки сохраняются в этом приложении или браузере.',
            'Тек оқу мысалын пайдаланыңыз. Оқушылардың деректерін енгізбеңіз. Жауаптар мен бағалар осы қолданбада не браузерде сақталады.',
          ),
          style: BuilderType.small,
        ),
        const SizedBox(height: 12),
        SelectableText(review.prompt, key: const Key('transfer.prompt')),
        const SizedBox(height: 8),
        BuilderButton(
          key: const Key('transfer.copyPrompt'),
          label: cs.t('Копировать запрос', 'Сұрауды көшіру'),
          onPressed: _saving
              ? null
              : () => _save(
                  (current) => current,
                  then: (current) async {
                    await Clipboard.setData(ClipboardData(text: current.prompt));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(cs.t('Запрос скопирован', 'Сұрау көшірілді')),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        BuilderButton(
          key: const Key('practice.openAgentsForTransfer'),
          label: cs.t('Открыть «Мои агенты»', '«Менің агенттерім» бөлімі'),
          onPressed: _saving ? null : widget.openAgents,
        ),
        const SizedBox(height: 12),
        if (review.firstAnswer.isEmpty)
          _capture(
            id: 'first',
            label: cs.t('Вставьте первый ответ второго агента', 'Екінші агенттің алғашқы жауабын енгізіңіз'),
            controller: _first,
            cs: cs,
            save: (value) => _save((current) => current.copyWith(firstAnswer: value)),
          )
        else ...[
          _answer('first', firstTitle, review.firstAnswer),
          const SizedBox(height: 12),
          _checklist(cs, review, second: false),
        ],
        if (review.firstReviewed && review.instructionChange.isEmpty)
          _capture(
            id: 'edit',
            label: cs.t('В настройках агента измените одно правило. Что изменили?', 'Агент баптауында бір ережені өзгертіңіз. Нені өзгерттіңіз?'),
            controller: _instruction,
            cs: cs,
            save: (value) => _save((current) => current.copyWith(instructionChange: value)),
            maxLength: 600,
          ),
        if (review.instructionChange.isNotEmpty) ...[
          const SizedBox(height: 12),
          _answer('edit', editTitle, review.instructionChange),
          const SizedBox(height: 12),
          if (review.secondAnswer.isEmpty)
            _capture(
              id: 'repeat',
              label: cs.t('Отправьте тот же запрос тому же агенту и вставьте ответ', 'Сол сұрауды сол агентке қайта жіберіп, жауабын енгізіңіз'),
              controller: _second,
              cs: cs,
              save: (value) => _save((current) => current.copyWith(secondAnswer: value)),
            )
          else ...[
            _answer('repeat', secondTitle, review.secondAnswer),
            const SizedBox(height: 12),
            _checklist(cs, review, second: true),
          ],
        ],
        if (review.change case final change?)
          Text(
            _result(cs, change),
            key: const Key('transfer.comparison'),
            style: BuilderType.title,
          ),
        if (_saveFailed)
          Text(
            cs.t('Не удалось сохранить. Повторите действие.', 'Сақтау мүмкін болмады. Қайталап көріңіз.'),
            key: const Key('transfer.saveError'),
            style: BuilderType.body,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = CourseStrings.of(context);
    final provider = transferReviewProvider(widget.ownerId);
    return ref.watch(provider).when(
      data: (saved) => _content(cs, saved),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => BuilderButton(
        label: cs.t('Повторить загрузку проверки', 'Тексеруді қайта жүктеу'),
        onPressed: () => ref.invalidate(provider),
      ),
    );
  }
}
