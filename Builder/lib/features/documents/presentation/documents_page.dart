import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/artifact_transfer_controller.dart';
import '../application/document_controller.dart';
import '../application/document_work_service.dart';
import '../domain/document_models.dart';
import '../domain/document_problem.dart';
import '../domain/document_work.dart';

class _NewTask {
  const _NewTask(this.file, this.skill, this.parameters, this.outputs);
  final PickedDocument file;
  final DocumentSkill skill;
  final DocumentParameters parameters;
  final List<DocumentFormat> outputs;
}

class DocumentsPage extends ConsumerStatefulWidget {
  const DocumentsPage({super.key, required this.ownerId});
  final String ownerId;
  @override
  ConsumerState<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends ConsumerState<DocumentsPage> {
  bool get _kk => Localizations.localeOf(context).languageCode == 'kk';
  String _text(String ru, String kk) => _kk ? kk : ru;

  DocumentController get _controller =>
      ref.read(documentControllerProvider(widget.ownerId).notifier);

  String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ${_text('МБ', 'МБ')}'
      : '${(bytes / 1024).ceil()} ${_text('КБ', 'КБ')}';

  Future<void> _newTask([DocumentWork? again]) async {
    final task = await showDialog<_NewTask>(
      context: context,
      builder: (_) => _NewTaskDialog(kk: _kk, again: again),
    );
    if (task == null || !mounted) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConsentDialog(kk: _kk, fileName: task.file.name),
    );
    if (agreed != true || !mounted) return;
    try {
      await _controller.start(
        file: task.file,
        skill: task.skill,
        parameters: task.parameters,
        outputs: task.outputs,
      );
    } on DocumentStartException catch (error) {
      _message(error.problem.text(kk: _kk));
    } on ArgumentError {
      _message(_text('Проверьте параметры задания.', 'Тапсырма параметрлерін тексеріңіз.'));
    } catch (_) {
      _message(DocumentProblem.unknown.text(kk: _kk));
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _remove(DocumentWork work) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text('Удалить задание?', 'Тапсырманы жою керек пе?')),
        content: Text(
          _text(
            'Файлы задания будут удалены с сервера CraftAI.',
            'Тапсырма файлдары CraftAI серверінен жойылады.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_text('Отмена', 'Болдырмау')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_text('Удалить', 'Жою')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.remove(work.id);
  }

  String _skillName(DocumentSkill skill) => switch (skill) {
    DocumentSkill.quiz => _text('Тест', 'Тест'),
    DocumentSkill.lessonPlan => _text('План урока', 'Сабақ жоспары'),
  };

  String _statusText(DocumentWork work) {
    if (work.waiting) {
      return DocumentProblem.fromCode(work.problemCode).text(kk: _kk);
    }
    switch (work.stage) {
      case DocumentStage.staged:
        return _text('Отправляется в CraftAI…', 'CraftAI-ға жіберіліп жатыр…');
      case DocumentStage.uploaded:
        return _text('Файл принят, создаётся задание…', 'Файл қабылданды, тапсырма жасалып жатыр…');
      case DocumentStage.submitted:
        return switch (work.remoteStatus) {
          DocumentJobStatus.parsing => _text('Читаю документ…', 'Құжат оқылып жатыр…'),
          DocumentJobStatus.generating => _text('Готовлю содержимое…', 'Мазмұн дайындалып жатыр…'),
          DocumentJobStatus.assembling => _text('Собираю DOCX и PDF…', 'DOCX және PDF жиналып жатыр…'),
          _ => _text('В очереди…', 'Кезекте…'),
        };
      case DocumentStage.succeeded:
        return _text('Готово', 'Дайын');
      case DocumentStage.canceled:
        return _text('Отменено', 'Болдырылмады');
      case DocumentStage.expired:
      case DocumentStage.failed:
        return DocumentProblem.fromCode(work.problemCode).text(kk: _kk);
    }
  }

  Future<void> _act(DocumentArtifact artifact, ArtifactAction action) async {
    final result = await ref
        .read(artifactTransferProvider(widget.ownerId).notifier)
        .perform(artifact, action);
    if (!mounted) return;
    switch (result) {
      case ArtifactResult.saved:
        _message(_text('Файл сохранён.', 'Файл сақталды.'));
      case ArtifactResult.noAppToOpen:
        _message(_text(
          'На устройстве нет приложения для этого формата. Сохраните файл или отправьте его через «Поделиться».',
          'Құрылғыда бұл пішімге арналған қолданба жоқ. Файлды сақтаңыз немесе «Бөлісу» арқылы жіберіңіз.',
        ));
      case ArtifactResult.failed:
        _message(_text('Не удалось выполнить действие с файлом.', 'Файлмен әрекетті орындау мүмкін болмады.'));
      case ArtifactResult.downloadFailed:
      case ArtifactResult.done:
      case ArtifactResult.cancelledByUser:
        break;
    }
  }

  Widget _artifactTile(DocumentArtifact artifact) {
    final transfer = ref.watch(artifactTransferProvider(widget.ownerId))[artifact.id];
    final downloading = transfer?.phase == TransferPhase.downloading;
    final id = artifact.id;
    return Column(
      key: ValueKey(id),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            artifact.format == DocumentFormat.pdf ? Icons.picture_as_pdf : Icons.description,
          ),
          title: Text(artifact.fileName),
          subtitle: Text(
            '${artifact.format.wire.toUpperCase()} · ${_size(artifact.sizeBytes)} · '
            '${_text('на сервере до', 'серверде мына уақытқа дейін')} '
            '${DateTime.parse(artifact.expiresAtUtc).toLocal().toString().substring(0, 16)}',
          ),
        ),
        if (downloading) ...[
          LinearProgressIndicator(value: transfer!.fraction),
          Text(
            '${_text('Скачивание', 'Жүктеу')}: ${_size(transfer.received)} / ${_size(transfer.total)}',
          ),
        ],
        if (transfer?.phase == TransferPhase.failed && transfer?.problem != null)
          Text(
            transfer!.problem!.text(kk: _kk),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Wrap(
          spacing: 8,
          children: [
            if (downloading)
              OutlinedButton(
                key: Key('artifact.cancel.$id'),
                onPressed: () => ref
                    .read(artifactTransferProvider(widget.ownerId).notifier)
                    .cancel(id),
                child: Text(_text('Отменить скачивание', 'Жүктеуді болдырмау')),
              )
            else ...[
              TextButton.icon(
                key: Key('artifact.open.$id'),
                onPressed: () => _act(artifact, ArtifactAction.open),
                icon: const Icon(Icons.open_in_new),
                label: Text(_text('Открыть', 'Ашу')),
              ),
              TextButton.icon(
                key: Key('artifact.save.$id'),
                onPressed: () => _act(artifact, ArtifactAction.save),
                icon: const Icon(Icons.save_alt),
                label: Text(_text('Сохранить', 'Сақтау')),
              ),
              TextButton.icon(
                key: Key('artifact.share.$id'),
                onPressed: () => _act(artifact, ArtifactAction.share),
                icon: const Icon(Icons.share),
                label: Text(_text('Поделиться', 'Бөлісу')),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _card(DocumentWork work) {
    final problem = DocumentProblem.fromCode(work.problemCode);
    final failed = work.stage == DocumentStage.failed || work.stage == DocumentStage.expired;
    return Card(
      key: ValueKey(work.id),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(work.fileName, style: Theme.of(context).textTheme.titleSmall),
            Text('${_skillName(work.skill)} · ${_size(work.sizeBytes)}'),
            const SizedBox(height: 8),
            Text(_statusText(work)),
            if (work.isActive && !work.waiting)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  value: work.progress == null ? null : work.progress! / 100,
                ),
              ),
            if (failed && problem.needsAnotherFile)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _text('Выберите другой файл.', 'Басқа файлды таңдаңыз.'),
                ),
              ),
            for (final artifact in work.artifacts) _artifactTile(artifact),
            Wrap(
              spacing: 8,
              children: [
                if (work.isActive)
                  OutlinedButton(
                    onPressed: () => _controller.cancel(work.id),
                    child: Text(_text('Отменить', 'Болдырмау')),
                  ),
                if (work.isActive && work.waiting)
                  TextButton(
                    onPressed: () => _controller.retryNow(work.id),
                    child: Text(_text('Повторить сейчас', 'Қазір қайталау')),
                  ),
                if (!work.isActive && work.stage != DocumentStage.succeeded)
                  TextButton(
                    onPressed: () => _newTask(work),
                    child: Text(_text('Начать заново', 'Қайта бастау')),
                  ),
                if (!work.isActive)
                  TextButton(
                    onPressed: () => _remove(work),
                    child: Text(_text('Удалить', 'Жою')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentControllerProvider(widget.ownerId));
    return Scaffold(
      appBar: AppBar(title: Text(_text('Документы DOCX и PDF', 'DOCX және PDF құжаттары'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTask,
        icon: const Icon(Icons.upload_file),
        label: Text(_text('Добавить файл', 'Файл қосу')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text(
            _text(
              'Файл (TXT, DOCX или PDF с текстом, до 10 МБ) передаётся на сервер CraftAI и обрабатывается там; приложение его не разбирает. '
              'Исходный файл удаляется в течение часа, готовые документы хранятся 24 часа. Это вложение для одной задачи: оно не попадает в «Знания».',
              'Файл (TXT, DOCX немесе мәтіні бар PDF, 10 МБ-қа дейін) CraftAI серверіне жіберіліп, сонда өңделеді; қолданба оны талдамайды. '
              'Бастапқы файл бір сағат ішінде жойылады, дайын құжаттар 24 сағат сақталады. Бұл бір тапсырмаға арналған тіркеме: ол «Білімге» түспейді.',
            ),
          ),
          const SizedBox(height: 12),
          if (state.loaded && state.items.isEmpty)
            Text(_text('Заданий пока нет.', 'Тапсырмалар әлі жоқ.')),
          for (final work in state.items) _card(work),
        ],
      ),
    );
  }
}

class _ConsentDialog extends StatelessWidget {
  const _ConsentDialog({required this.kk, required this.fileName});
  final bool kk;
  final String fileName;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(kk ? 'Файлды жіберу' : 'Передача файла'),
    content: Text(
      kk
          ? '«$fileName» файлы құжат жасау үшін CraftAI серверіне жіберіліп, сонда өңделеді. Мәтіннің қажетті бөлігі OpenRouter арқылы ЖИ моделіне жіберілуі мүмкін. Файл мен мәтін өңдеуден кейін бір сағат ішінде жойылады, дайын құжаттар 24 сағат сақталады. Оқушылардың жеке деректері бар файлдарды жүктемеңіз.'
          : 'Чтобы создать документ, файл «$fileName» будет передан на сервер CraftAI и обработан там. Нужная часть текста может быть отправлена модели ИИ через OpenRouter. Файл и текст удаляются в течение часа после обработки, готовые документы хранятся 24 часа. Не загружайте файлы с персональными данными учеников.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(kk ? 'Болдырмау' : 'Отмена'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(kk ? 'Келісемін, жіберу' : 'Согласен, отправить'),
      ),
    ],
  );
}

class _NewTaskDialog extends ConsumerStatefulWidget {
  const _NewTaskDialog({required this.kk, this.again});
  final bool kk;
  final DocumentWork? again;
  @override
  ConsumerState<_NewTaskDialog> createState() => _NewTaskDialogState();
}

class _NewTaskDialogState extends ConsumerState<_NewTaskDialog> {
  PickedDocument? _file;
  DocumentProblem? _fileProblem;
  late DocumentSkill _skill;
  late String _language;
  late final TextEditingController _topic;
  late final TextEditingController _items;
  int? _grade;
  late bool _docx;
  late bool _pdf;
  String? _error;

  String t(String ru, String kk) => widget.kk ? kk : ru;

  @override
  void initState() {
    super.initState();
    final again = widget.again;
    _skill = again?.skill ?? DocumentSkill.quiz;
    _language = again?.parameters.language ?? (widget.kk ? 'kk' : 'ru');
    _topic = TextEditingController(text: again?.parameters.topic ?? '');
    _items = TextEditingController(text: '${again?.parameters.itemsCount ?? 10}');
    _grade = again?.parameters.grade;
    _docx = again?.outputs.contains(DocumentFormat.docx) ?? true;
    _pdf = again?.outputs.contains(DocumentFormat.pdf) ?? true;
  }

  @override
  void dispose() {
    _topic.dispose();
    _items.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await ref.read(documentPickerProvider).pick();
    if (picked == null || !mounted) return;
    final problem = checkSourceFile(picked.name, picked.sizeBytes);
    setState(() {
      _file = picked;
      _fileProblem = switch (problem) {
        null => null,
        SourceFileProblem.unsupportedType => DocumentProblem.unsupportedType,
        SourceFileProblem.tooLarge => DocumentProblem.tooLarge,
        SourceFileProblem.empty => DocumentProblem.corrupt,
      };
    });
  }

  void _continue() {
    final file = _file;
    if (file == null || _fileProblem != null) {
      setState(() => _error = t('Выберите файл TXT, DOCX или PDF.', 'TXT, DOCX немесе PDF файлын таңдаңыз.'));
      return;
    }
    final outputs = [if (_docx) DocumentFormat.docx, if (_pdf) DocumentFormat.pdf];
    if (outputs.isEmpty) {
      setState(() => _error = t('Выберите хотя бы один формат.', 'Кемінде бір пішімді таңдаңыз.'));
      return;
    }
    final items = int.tryParse(_items.text.trim());
    final parameters = DocumentParameters(
      language: _language,
      topic: _topic.text.trim().isEmpty ? null : _topic.text.trim(),
      grade: _grade,
      itemsCount: _skill == DocumentSkill.quiz ? items : null,
    );
    if (parameters.validate() != null) {
      setState(() => _error = t('Проверьте тему, класс и число вопросов (1–30).', 'Тақырыпты, сыныпты және сұрақ санын (1–30) тексеріңіз.'));
      return;
    }
    Navigator.pop(context, _NewTask(file, _skill, parameters, outputs));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t('Новое задание', 'Жаңа тапсырма')),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.attach_file),
              label: Text(_file?.name ?? t('Выбрать файл', 'Файлды таңдау')),
            ),
            if (_fileProblem != null)
              Text(
                _fileProblem!.text(kk: widget.kk),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DocumentSkill>(
              initialValue: _skill,
              decoration: InputDecoration(labelText: t('Что создать', 'Не жасау керек')),
              items: [
                DropdownMenuItem(value: DocumentSkill.quiz, child: Text(t('Тест', 'Тест'))),
                DropdownMenuItem(value: DocumentSkill.lessonPlan, child: Text(t('План урока', 'Сабақ жоспары'))),
              ],
              onChanged: (value) => setState(() => _skill = value ?? _skill),
            ),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: InputDecoration(labelText: t('Язык документа', 'Құжат тілі')),
              items: const [
                DropdownMenuItem(value: 'ru', child: Text('Русский')),
                DropdownMenuItem(value: 'kk', child: Text('Қазақша')),
              ],
              onChanged: (value) => setState(() => _language = value ?? _language),
            ),
            TextField(
              controller: _topic,
              maxLength: 200,
              decoration: InputDecoration(labelText: t('Тема (необязательно)', 'Тақырып (міндетті емес)')),
            ),
            DropdownButtonFormField<int?>(
              initialValue: _grade,
              decoration: InputDecoration(labelText: t('Класс', 'Сынып')),
              items: [
                DropdownMenuItem(value: null, child: Text(t('Не указан', 'Көрсетілмеген'))),
                for (var g = 1; g <= 11; g++) DropdownMenuItem(value: g, child: Text('$g')),
              ],
              onChanged: (value) => setState(() => _grade = value),
            ),
            if (_skill == DocumentSkill.quiz)
              TextField(
                controller: _items,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t('Число вопросов (1–30)', 'Сұрақ саны (1–30)')),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _docx,
              title: const Text('DOCX'),
              onChanged: (value) => setState(() => _docx = value ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _pdf,
              title: const Text('PDF'),
              onChanged: (value) => setState(() => _pdf = value ?? false),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('Отмена', 'Болдырмау')),
      ),
      FilledButton(onPressed: _continue, child: Text(t('Продолжить', 'Жалғастыру'))),
    ],
  );
}
