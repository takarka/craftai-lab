import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../services/llm_service.dart';
import '../../services/model_manager_service.dart';

class ModelManagementScreen extends StatefulWidget {
  final ModelManagerService modelManager;
  final LLMService llmService;

  const ModelManagementScreen({
    super.key,
    required this.modelManager,
    required this.llmService,
  });

  @override
  State<ModelManagementScreen> createState() => _ModelManagementScreenState();
}

class _ModelManagementScreenState extends State<ModelManagementScreen> {
  String _selectedFamily = 'Все';

  @override
  void initState() {
    super.initState();
    widget.modelManager.refreshLocalModels();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelManager = widget.modelManager;
    final llmService = widget.llmService;

    final filteredPresets = _selectedFamily == 'Все'
        ? AppConstants.presetModels
        : AppConstants.presetModels
            .where((p) => p['family'] == _selectedFamily)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление моделями ИИ'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([modelManager, llmService]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Current Loaded Status Card
              Card(
                elevation: 0,
                color: llmService.isModelLoaded
                    ? Colors.green.withValues(alpha: 0.12)
                    : theme.colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: llmService.isModelLoaded
                        ? Colors.green.withValues(alpha: 0.4)
                        : Colors.transparent,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            llmService.isModelLoaded
                                ? Icons.check_circle_rounded
                                : Icons.info_outline_rounded,
                            color: llmService.isModelLoaded
                                ? Colors.green
                                : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              llmService.isModelLoaded
                                  ? 'Модель активна в памяти'
                                  : 'Модель не загружена',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        llmService.isModelLoaded
                            ? '${llmService.currentModelName} • ${llmService.threads} потока CPU'
                            : llmService.loadStatus.isNotEmpty
                                ? llmService.loadStatus
                                : 'Выберите модель из локальных файлов или скачайте пресет ниже.',
                        style: theme.textTheme.bodyMedium,
                      ),

                      const SizedBox(height: 12),

                      // CPU Thread Selection
                      Row(
                        children: [
                          Text(
                            'Потоков CPU: ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SegmentedButton<int>(
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            segments: const [
                              ButtonSegment(
                                value: 2,
                                label: Text('2 (эконом)'),
                              ),
                              ButtonSegment(
                                value: 4,
                                label: Text('4 (оптимально)'),
                              ),
                              ButtonSegment(
                                value: 6,
                                label: Text('6 (макс)'),
                              ),
                            ],
                            selected: {llmService.threads},
                            onSelectionChanged: (set) {
                              llmService.setThreads(set.first);
                            },
                          ),
                        ],
                      ),

                      if (llmService.isLoadingModel) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                      if (llmService.isModelLoaded) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => llmService.unloadModel(),
                          icon: const Icon(Icons.eject_rounded, size: 18),
                          label: const Text('Выгрузить из RAM'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 2. Download Progress (if active)
              if (modelManager.isDownloading) ...[
                Card(
                  elevation: 0,
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Загрузка модели...',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              onPressed: () => modelManager.cancelDownload(),
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Отмена',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: modelManager.downloadProgress > 0
                              ? modelManager.downloadProgress
                              : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          modelManager.downloadStatusText,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // 3. Local Files on Phone
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Локальные модели (.gguf)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final importedPath =
                          await modelManager.pickLocalModelFile();
                      if (importedPath != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Файл импортирован!')),
                        );
                      }
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('Выбрать с телефона'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (modelManager.localModels.isEmpty)
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'В папке приложения пока нет файлов .gguf. '
                      'Вы можете скачать пресет ниже или нажать "Выбрать с телефона" '
                      'для выбора уже загруженного файла.',
                    ),
                  ),
                )
              else
                ...modelManager.localModels.map((m) {
                  final isThisLoaded =
                      llmService.isModelLoaded &&
                      llmService.currentModelName == m.name;

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    color: isThisLoaded
                        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                        : theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.memory_rounded,
                                color: isThisLoaded
                                    ? theme.colorScheme.primary
                                    : theme.iconTheme.color,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  m.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Размер: ${m.formattedSize}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (!isThisLoaded)
                                FilledButton.tonal(
                                  onPressed: llmService.isLoadingModel
                                      ? null
                                      : () async {
                                          final success =
                                              await llmService.loadModel(
                                            modelPath: m.path,
                                            modelDisplayName: m.name,
                                          );
                                          if (success && context.mounted) {
                                            Navigator.pop(context);
                                          }
                                        },
                                  child: const Text('Загрузить в память'),
                                )
                              else
                                const Chip(
                                  label: Text('Активна в RAM'),
                                  backgroundColor: Colors.green,
                                  labelStyle: TextStyle(color: Colors.white),
                                ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 20),
                                tooltip: 'Удалить',
                                onPressed: isThisLoaded
                                    ? null
                                    : () => modelManager.deleteModel(m.path),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 24),

              // 4. Preset Models Section with Filter Chips
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Каталог моделей',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Family Filter Tabs
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final family in ['Все', 'Qwen', 'Gemma'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: _selectedFamily == family,
                          avatar: family == 'Gemma'
                              ? const Icon(Icons.scatter_plot_rounded, size: 16)
                              : (family == 'Qwen'
                                  ? const Icon(Icons.auto_awesome, size: 16)
                                  : null),
                          label: Text(
                            family == 'Gemma'
                                ? 'Google Gemma (${AppConstants.presetModels.where((p) => p['family'] == 'Gemma').length})'
                                : (family == 'Qwen'
                                    ? 'Alibaba Qwen (${AppConstants.presetModels.where((p) => p['family'] == 'Qwen').length})'
                                    : 'Все (${AppConstants.presetModels.length})'),
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedFamily = family;
                              });
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              ...filteredPresets.map((preset) {
                final fileName = preset['fileName']!;
                final family = preset['family'] ?? 'Qwen';
                final isAlreadyDownloaded = modelManager.localModels
                    .any((m) => m.name == fileName);

                final isGemma = family == 'Gemma';

                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isGemma
                                    ? Colors.blue.withValues(alpha: 0.2)
                                    : Colors.deepPurple.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isGemma ? 'GOOGLE' : 'QWEN',
                                style: TextStyle(
                                  color: isGemma
                                      ? Colors.blueAccent
                                      : Colors.deepPurpleAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                preset['name']!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                preset['size']!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          preset['description']!,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        if (isAlreadyDownloaded)
                          const Row(
                            children: [
                              Icon(Icons.check_circle,
                                  color: Colors.green, size: 16),
                              SizedBox(width: 6),
                              Text('Уже скачана в память'),
                            ],
                          )
                        else
                          FilledButton.icon(
                            onPressed: modelManager.isDownloading
                                ? null
                                : () => modelManager.downloadModel(
                                      url: preset['url']!,
                                      targetFileName: fileName,
                                    ),
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Скачать модель'),
                          ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 16),

              // 5. ADB Push Tip Card
              Card(
                elevation: 0,
                color: Colors.blue.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Colors.blue.withValues(alpha: 0.3),
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.usb_rounded, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Быстрая передача моделей по USB (ADB)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Любой GGUF файл (Qwen, Gemma, Llama) можно за секунды передать через компьютер:\n'
                        'adb push имя_файла.gguf /sdcard/Download/\n'
                        'Затем нажмите кнопку «Выбрать с телефона» выше.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
