import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/lab_run_models.dart';
import '../infrastructure/lab_runtime_api.dart';

class LabPickedPhoto {
  final String fileName;
  final List<int> bytes;

  const LabPickedPhoto({required this.fileName, required this.bytes});
}

class LabPhotoPermissionDeniedException implements Exception {
  final String message;
  const LabPhotoPermissionDeniedException([
    this.message = 'Доступ к камере или фото отклонён. Черновик сохранён.',
  ]);
}

typedef LabPhotoPicker = Future<LabPickedPhoto?> Function();

class LabPhotoRouteInfoPage extends StatelessWidget {
  const LabPhotoRouteInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Маршрут обработки фото')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(
            leading: Icon(Icons.upload_file),
            title: Text('1. Передача на сервер CraftAI Lab'),
            subtitle: Text(
              'Проверяется формат (JPEG/PNG по сигнатуре) и размер ≤ 10 МБ.',
            ),
          ),
          ListTile(
            leading: Icon(Icons.document_scanner_outlined),
            title: Text('2. Извлечение текста'),
            subtitle: Text(
              'Текст извлекается на сервере Lab и возвращается вам на проверку перед сохранением.',
            ),
          ),
          ListTile(
            leading: Icon(Icons.auto_delete_outlined),
            title: Text('3. Удаление исходного фото'),
            subtitle: Text(
              'Исходный файл изображения автоматически удаляется через 24 часа.',
            ),
          ),
        ],
      ),
    );
  }
}

class LabAgentSettingsPage extends StatefulWidget {
  final String agentId;
  final LabRuntimeApi api;
  final List<LabModelInfo> availableModels;
  final String initialModelId;
  final String initialInstruction;
  final bool initialAllowSave;
  final bool initialAllowSearch;
  final LabPhotoPicker? photoPicker;
  final void Function({
    required String modelId,
    required String instruction,
    required bool allowSave,
    required bool allowSearch,
  })? onSaveCoreSettings;

  const LabAgentSettingsPage({
    super.key,
    required this.agentId,
    required this.api,
    required this.availableModels,
    required this.initialModelId,
    required this.initialInstruction,
    required this.initialAllowSave,
    required this.initialAllowSearch,
    this.photoPicker,
    this.onSaveCoreSettings,
  });

  @override
  State<LabAgentSettingsPage> createState() => _LabAgentSettingsPageState();
}

class _LabAgentSettingsPageState extends State<LabAgentSettingsPage> {
  late String _modelId;
  late bool _allowSave;
  late bool _allowSearch;
  late final TextEditingController _instructionCtrl;
  late final TextEditingController _materialTitleCtrl;
  late final TextEditingController _materialContentCtrl;
  late final TextEditingController _memoryCtrl;

  List<LabMaterialItem> _materials = const [];
  List<LabMemoryItem> _memory = const [];
  List<LabSkillItem> _skills = const [];
  String? _statusMessage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _modelId = widget.initialModelId;
    _allowSave = widget.initialAllowSave;
    _allowSearch = widget.initialAllowSearch;
    _instructionCtrl = TextEditingController(text: widget.initialInstruction);
    _materialTitleCtrl = TextEditingController();
    _materialContentCtrl = TextEditingController();
    _memoryCtrl = TextEditingController();
    _loadAll();
  }

  @override
  void dispose() {
    _instructionCtrl.dispose();
    _materialTitleCtrl.dispose();
    _materialContentCtrl.dispose();
    _memoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.listMaterials(widget.agentId),
        widget.api.listMemory(widget.agentId),
        widget.api.listSkills(widget.agentId),
      ]);
      if (!mounted) return;
      setState(() {
        _materials = results[0] as List<LabMaterialItem>;
        _memory = results[1] as List<LabMemoryItem>;
        _skills = results[2] as List<LabSkillItem>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Не удалось загрузить данные настроек: $e';
        _loading = false;
      });
    }
  }

  Future<void> _pickAndExtractPhoto() async {
    final picker = widget.photoPicker;
    if (picker == null) return;
    try {
      final photo = await picker();
      if (photo == null) return;
      final extracted = await widget.api.uploadPhoto(
        agentId: widget.agentId,
        fileName: photo.fileName,
        bytes: photo.bytes,
      );
      if (!mounted) return;
      // Put extracted text into the editable material draft for user review (never auto-saved!)
      setState(() {
        if (_materialTitleCtrl.text.trim().isEmpty) {
          _materialTitleCtrl.text = 'Текст с фото';
        }
        _materialContentCtrl.text = extracted.extractedText;
        _statusMessage =
            'Текст извлечён для проверки. Отредактируйте и нажмите «Сохранить материал».';
      });
    } on LabPhotoPermissionDeniedException catch (e) {
      if (!mounted) return;
      // Drafts (_materialTitleCtrl / _materialContentCtrl) remain intact
      setState(() {
        _statusMessage = e.message;
      });
    } on PlatformException {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Доступ к камере отклонён. Черновик сохранён.';
      });
    } on LabApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.message;
      });
    }
  }

  Future<void> _saveMaterial() async {
    final title = _materialTitleCtrl.text.trim();
    final content = _materialContentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) return;
    if (content.length > 10000) {
      setState(() {
        _statusMessage = 'Материал превышает лимит 10 000 знаков.';
      });
      return;
    }
    try {
      final created = await widget.api.createMaterial(
        agentId: widget.agentId,
        title: title,
        content: content,
      );
      if (!mounted) return;
      setState(() {
        _materials = [created, ..._materials];
        _materialTitleCtrl.clear();
        _materialContentCtrl.clear();
        _statusMessage = 'Материал сохранён.';
      });
    } on LabApiException catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedModel = widget.availableModels.where((m) => m.modelId == _modelId).firstOrNull;
    final toolsIncompatible =
        selectedModel != null && (_allowSave || _allowSearch) && !selectedModel.supportsTools;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки агента'),
        actions: [
          TextButton(
            onPressed: () {
              widget.onSaveCoreSettings?.call(
                modelId: _modelId,
                instruction: _instructionCtrl.text,
                allowSave: _allowSave,
                allowSearch: _allowSearch,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Настройки применены')),
              );
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_statusMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Text(_statusMessage!),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Модель', style: Theme.of(context).textTheme.titleMedium),
                      RadioGroup<String>(
                        groupValue: _modelId,
                        onChanged: (val) {
                          if (val != null) setState(() => _modelId = val);
                        },
                        child: Column(
                          children: [
                            for (final m in widget.availableModels)
                              RadioListTile<String>(
                                value: m.modelId,
                                title: Text(m.modelId),
                                subtitle: Text(
                                  'Инструменты: ${m.supportsTools ? "да" : "нет"} · Фото: ${m.supportsVision ? "да" : "нет"}',
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (toolsIncompatible)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Выбранная модель не поддерживает инструменты. Отправка будет заблокирована.',
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      const Divider(),
                      Text('Инструменты', style: Theme.of(context).textTheme.titleMedium),
                      SwitchListTile(
                        title: const Text('Сохранение материалов (save_material)'),
                        value: _allowSave,
                        onChanged: (v) => setState(() => _allowSave = v),
                      ),
                      SwitchListTile(
                        title: const Text('Поиск по материалам (search_materials)'),
                        value: _allowSearch,
                        onChanged: (v) => setState(() => _allowSearch = v),
                      ),
                      const Divider(),
                      Text('Инструкция (${_instructionCtrl.text.length}/5000)',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _instructionCtrl,
                        maxLength: 5000,
                        maxLines: 4,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Материалы', style: Theme.of(context).textTheme.titleMedium),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const LabPhotoRouteInfoPage(),
                                ),
                              );
                            },
                            child: const Text('Маршрут фото'),
                          ),
                        ],
                      ),
                      TextField(
                        controller: _materialTitleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Название материала',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('material_content_field'),
                        controller: _materialContentCtrl,
                        maxLength: 10000,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Текст материала (≤ 10 000)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _saveMaterial,
                            child: const Text('Сохранить материал'),
                          ),
                          if (widget.photoPicker != null)
                            OutlinedButton.icon(
                              onPressed: _pickAndExtractPhoto,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Извлечь с фото'),
                            ),
                        ],
                      ),
                      for (final mat in _materials)
                        ListTile(
                          title: Text(mat.title),
                          subtitle: Text(mat.content, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await widget.api.deleteMaterial(
                                agentId: widget.agentId,
                                materialId: mat.id,
                              );
                              setState(() {
                                _materials = _materials.where((e) => e.id != mat.id).toList();
                              });
                            },
                          ),
                        ),
                      const Divider(),
                      Text('Скиллы', style: Theme.of(context).textTheme.titleMedium),
                      for (final sk in _skills)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SwitchListTile(
                                  title: Text('${sk.title} (v${sk.version}, rev ${sk.revision})'),
                                  subtitle: Text(sk.baseContent),
                                  value: sk.enabled,
                                  onChanged: (val) async {
                                    final updated = await widget.api.updateSkill(
                                      agentId: widget.agentId,
                                      slug: sk.slug,
                                      enabled: val,
                                      overrideText: sk.overrideText,
                                      allowSave: _allowSave,
                                      allowSearch: _allowSearch,
                                    );
                                    setState(() {
                                      _skills = _skills
                                          .map((e) => e.slug == sk.slug ? updated : e)
                                          .toList();
                                    });
                                  },
                                ),
                                for (final c in sk.collisions)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    child: Text(
                                      c,
                                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const Divider(),
                      Text('Память', style: Theme.of(context).textTheme.titleMedium),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _memoryCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Добавить факт памяти...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              final txt = _memoryCtrl.text.trim();
                              if (txt.isEmpty) return;
                              final item = await widget.api.createMemory(
                                agentId: widget.agentId,
                                content: txt,
                              );
                              setState(() {
                                _memory = [item, ..._memory];
                                _memoryCtrl.clear();
                              });
                            },
                            child: const Text('Добавить'),
                          ),
                        ],
                      ),
                      for (final m in _memory)
                        ListTile(
                          title: Text(m.content),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await widget.api.deleteMemory(
                                agentId: widget.agentId,
                                entryId: m.id,
                              );
                              setState(() {
                                _memory = _memory.where((e) => e.id != m.id).toList();
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

