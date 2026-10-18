import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui_kit/controls.dart';
import '../../../ui_kit/identity.dart';
import '../../../ui_kit/tokens.dart';
import '../../trace/presentation/trace_sheet.dart';
import '../domain/knowledge_models.dart';
import 'd03_personal_data_dialog.dart';
import 'knowledge_providers.dart';

/// Screen S41: База знаний ассистента и локальный RAG (F12-08, F12-V01).
///
/// Supports standard management mode and learn mode (Level 3 course practice).
class KnowledgePage extends ConsumerStatefulWidget {
  final String ownerId;
  final bool isLearningMode;
  final VoidCallback? onLearningCompleted;

  const KnowledgePage({
    super.key,
    required this.ownerId,
    this.isLearningMode = false,
    this.onLearningCompleted,
  });

  @override
  ConsumerState<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends ConsumerState<KnowledgePage> {
  final TextEditingController _queryController = TextEditingController();
  bool _testedFound = false;
  bool _testedNotFound = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(knowledgeControllerProvider(widget.ownerId));
    final controller = ref.read(
      knowledgeControllerProvider(widget.ownerId).notifier,
    );

    return Scaffold(
      backgroundColor: BuilderColors.background,
      appBar: AppBar(
        backgroundColor: BuilderColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: BuilderColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'База знаний',
              style: BuilderTypography.titleMedium.copyWith(
                color: BuilderColors.ink,
              ),
            ),
            Text(
              'Уровень 3 · Локальный RAG',
              style: BuilderTypography.labelSmall.copyWith(
                color: BuilderColors.inkSecondary,
              ),
            ),
          ],
        ),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => controller.loadDocuments(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(BuilderSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Learning mode header
                    if (widget.isLearningMode) ...[
                      _buildLearningHeader(),
                      const SizedBox(height: BuilderSpace.md),
                    ],

                    // Architecture Chips per F12-V01
                    _buildStorageChips(),
                    const SizedBox(height: BuilderSpace.md),

                    // Error banner
                    if (state.errorMessage != null) ...[
                      _buildErrorBanner(state.errorMessage!),
                      const SizedBox(height: BuilderSpace.md),
                    ],

                    // Documents Header & Add Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Документы (${state.documents.length})',
                          style: BuilderTypography.titleSmall.copyWith(
                            color: BuilderColors.ink,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        BuilderButton(
                          label: 'Добавить',
                          icon: BuilderGlyph.plus,
                          variant: BuilderButtonVariant.secondary,
                          onPressed: () => _openAddDialog(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: BuilderSpace.sm),

                    // Documents List or Empty State
                    if (state.documents.isEmpty)
                      _buildEmptyDocumentsCard(context)
                    else
                      ...state.documents.map(
                        (doc) => _buildDocumentCard(context, doc),
                      ),

                    const SizedBox(height: BuilderSpace.lg),
                    const Divider(color: BuilderColors.line),
                    const SizedBox(height: BuilderSpace.md),

                    // Test Search Section (F12-08)
                    _buildTestSearchSection(state, controller),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLearningHeader() {
    return Container(
      padding: const EdgeInsets.all(BuilderSpace.md),
      decoration: BoxDecoration(
        color: BuilderColors.accentBackground,
        borderRadius: BorderRadius.circular(BuilderRadii.card),
        border: Border.all(color: BuilderColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BuilderIcon(
                BuilderGlyph.course,
                size: 22,
                color: BuilderColors.accent,
              ),
              const SizedBox(width: BuilderSpace.xs),
              Text(
                'Практика: Уровень 3 — Знания и RAG',
                style: BuilderTypography.labelLarge.copyWith(
                  color: BuilderColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: BuilderSpace.xs),
          Text(
            '1. Добавьте учебный документ в базу знаний.\n'
            '2. Проверьте вопрос по теме документа — найдутся точные фрагменты.\n'
            '3. Проверьте посторонний вопрос — убедитесь, что ассистент не выдумывает ответ при отсутствии совпадений.',
            style: BuilderTypography.bodySmall.copyWith(
              color: BuilderColors.ink,
              height: 1.4,
            ),
          ),
          if (_testedFound && _testedNotFound) ...[
            const SizedBox(height: BuilderSpace.sm),
            Container(
              padding: const EdgeInsets.all(BuilderSpace.xs),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(BuilderRadii.control),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: BuilderSpace.xs),
                  Expanded(
                    child: Text(
                      'Практика завершена! Оба сценария (найдено / не найдено) проверены.',
                      style: BuilderTypography.bodySmall.copyWith(
                        color: Colors.green.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStorageChips() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: BuilderColors.primaryTint,
              borderRadius: BorderRadius.circular(BuilderRadii.chip),
              border: Border.all(
                color: BuilderColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const BuilderIcon(
                  BuilderGlyph.phone,
                  size: 16,
                  color: BuilderColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'На устройстве: индекс и файлы',
                    style: BuilderTypography.labelSmall.copyWith(
                      color: BuilderColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: BuilderSpace.xs),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: BuilderColors.warningTint,
              borderRadius: BorderRadius.circular(BuilderRadii.chip),
              border: Border.all(
                color: BuilderColors.warning.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const BuilderIcon(
                  BuilderGlyph.cloud,
                  size: 16,
                  color: BuilderColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'В облако: только фрагменты',
                    style: BuilderTypography.labelSmall.copyWith(
                      color: BuilderColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(BuilderSpace.sm),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(BuilderRadii.tile),
      ),
      child: Text(
        message,
        style: BuilderTypography.bodySmall.copyWith(color: Colors.red.shade900),
      ),
    );
  }

  Widget _buildEmptyDocumentsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BuilderSpace.lg),
      decoration: BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.circular(BuilderRadii.card),
        border: Border.all(color: BuilderColors.line),
      ),
      child: Column(
        children: [
          const BuilderIcon(
            BuilderGlyph.doc,
            size: 40,
            color: BuilderColors.inkDisabled,
          ),
          const SizedBox(height: BuilderSpace.sm),
          Text(
            'Нет подключенных документов',
            style: BuilderTypography.titleSmall.copyWith(
              color: BuilderColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Добавьте рабочую программу, расписание уроков или памятку, чтобы ассистент отвечал на их основе.',
            textAlign: TextAlign.center,
            style: BuilderTypography.bodySmall.copyWith(
              color: BuilderColors.inkSecondary,
            ),
          ),
          const SizedBox(height: BuilderSpace.md),
          BuilderButton(
            label: 'Добавить первый документ',
            icon: BuilderGlyph.plus,
            onPressed: () => _openAddDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(BuildContext context, KnowledgeDocument doc) {
    final controller = ref.read(
      knowledgeControllerProvider(widget.ownerId).notifier,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: BuilderSpace.xs),
      padding: const EdgeInsets.all(BuilderSpace.sm),
      decoration: BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.circular(BuilderRadii.tile),
        border: Border.all(color: BuilderColors.line),
      ),
      child: Row(
        children: [
          _buildFormatBadge(doc.fileFormat),
          const SizedBox(width: BuilderSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.fileName,
                  style: BuilderTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: doc.isEnabled
                        ? BuilderColors.ink
                        : BuilderColors.inkDisabled,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${doc.formattedSize} · ${doc.chunksCount} фрагментов',
                  style: BuilderTypography.bodySmall.copyWith(
                    color: BuilderColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Toggle search inclusion (F12-11)
          Switch(
            value: doc.isEnabled,
            activeTrackColor: BuilderColors.primary,
            onChanged: (val) =>
                controller.toggleDocument(docId: doc.id, isEnabled: val),
          ),
          // Delete button (F12-12)
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: BuilderColors.inkSecondary,
              size: 20,
            ),
            onPressed: () => _confirmDelete(context, doc),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatBadge(DocumentFormat format) {
    Color bg;
    Color fg;
    switch (format) {
      case DocumentFormat.pdf:
        bg = Colors.red.shade100;
        fg = Colors.red.shade900;
        break;
      case DocumentFormat.docx:
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade900;
        break;
      case DocumentFormat.txt:
        bg = Colors.grey.shade200;
        fg = BuilderColors.ink;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BuilderRadii.control),
      ),
      child: Text(
        format.label,
        style: BuilderTypography.labelSmall.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildTestSearchSection(
    KnowledgeState state,
    KnowledgeNotifier controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const BuilderIcon(
              BuilderGlyph.search,
              size: 20,
              color: BuilderColors.primary,
            ),
            const SizedBox(width: BuilderSpace.xs),
            Text(
              'Проверить поиск по знаниям',
              style: BuilderTypography.titleSmall.copyWith(
                color: BuilderColors.ink,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Протестируйте локальный поиск на телефоне. При релевантности ниже порога (35%) ассистент откажется от фантазий.',
          style: BuilderTypography.bodySmall.copyWith(
            color: BuilderColors.inkSecondary,
          ),
        ),
        const SizedBox(height: BuilderSpace.sm),

        // Quick suggestions
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildSuggestionChip(
                'Расписание уроков в понедельник',
                isMatch: true,
              ),
              const SizedBox(width: BuilderSpace.xs),
              _buildSuggestionChip('Лабораторная по биологии', isMatch: true),
              const SizedBox(width: BuilderSpace.xs),
              _buildSuggestionChip(
                'Правила техники безопасности',
                isMatch: true,
              ),
              const SizedBox(width: BuilderSpace.xs),
              _buildSuggestionChip(
                'Какая температура на Марсе?',
                isMatch: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: BuilderSpace.sm),

        // Query input
        TextField(
          controller: _queryController,
          decoration: InputDecoration(
            hintText: 'Введите тестовый вопрос...',
            filled: true,
            fillColor: BuilderColors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BuilderRadii.control),
              borderSide: const BorderSide(color: BuilderColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BuilderRadii.control),
              borderSide: const BorderSide(color: BuilderColors.line),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => _queryController.clear(),
            ),
          ),
        ),
        const SizedBox(height: BuilderSpace.sm),

        // Submit Button
        BuilderButton(
          label: state.isSearching
              ? 'Поиск и генерация...'
              : 'Найти и ответить',
          icon: BuilderGlyph.search,
          loading: state.isSearching,
          onPressed: () => _handleSearch(controller),
        ),

        // Results
        if (state.searchResult != null) ...[
          const SizedBox(height: BuilderSpace.md),
          _buildSearchResults(state),
        ],
      ],
    );
  }

  Widget _buildSuggestionChip(String query, {required bool isMatch}) {
    return ActionChip(
      label: Text(
        query,
        style: BuilderTypography.labelSmall.copyWith(
          color: isMatch ? BuilderColors.primary : BuilderColors.warning,
        ),
      ),
      backgroundColor: isMatch
          ? BuilderColors.primaryTint
          : BuilderColors.warningTint,
      side: BorderSide(
        color: isMatch
            ? BuilderColors.primary.withValues(alpha: 0.3)
            : BuilderColors.warning.withValues(alpha: 0.3),
      ),
      onPressed: () {
        _queryController.text = query;
      },
    );
  }

  Widget _buildSearchResults(KnowledgeState state) {
    final result = state.searchResult!;
    final matchedCount = result.matches.where((m) => m.isAboveThreshold).length;

    return Container(
      padding: const EdgeInsets.all(BuilderSpace.md),
      decoration: BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.circular(BuilderRadii.card),
        border: Border.all(
          color: result.hasRelevantMatches
              ? BuilderColors.primary.withValues(alpha: 0.4)
              : BuilderColors.warning,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Meta stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Результат поиска',
                style: BuilderTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$matchedCount найдено из ${result.totalScannedChunks} (${result.searchDurationMs} мс)',
                style: BuilderTypography.labelSmall.copyWith(
                  color: BuilderColors.inkSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: BuilderSpace.sm),

          if (result.hasRelevantMatches) ...[
            // Matched Chunks list
            Text(
              'Найденные фрагменты на устройстве:',
              style: BuilderTypography.labelSmall.copyWith(
                color: BuilderColors.inkSecondary,
              ),
            ),
            const SizedBox(height: 6),
            ...result.matches.where((m) => m.isAboveThreshold).map((match) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(BuilderSpace.xs),
                decoration: BoxDecoration(
                  color: BuilderColors.background,
                  borderRadius: BorderRadius.circular(BuilderRadii.control),
                  border: Border.all(color: BuilderColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${match.chunk.documentName} · стр. ${match.chunk.pageNumber}',
                          style: BuilderTypography.labelSmall.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(
                              BuilderRadii.chip,
                            ),
                          ),
                          child: Text(
                            match.scorePercentage,
                            style: BuilderTypography.labelSmall.copyWith(
                              color: Colors.green.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      match.chunk.chunkText,
                      style: BuilderTypography.bodySmall.copyWith(
                        color: BuilderColors.ink,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: BuilderSpace.sm),

            // Generated Answer
            if (state.generatedAnswer != null) ...[
              Text(
                'Ответ ассистента:',
                style: BuilderTypography.labelSmall.copyWith(
                  color: BuilderColors.inkSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(BuilderSpace.sm),
                decoration: BoxDecoration(
                  color: BuilderColors.primaryTint.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(BuilderRadii.tile),
                ),
                child: Text(
                  state.generatedAnswer!,
                  style: BuilderTypography.bodyMedium.copyWith(
                    color: BuilderColors.ink,
                  ),
                ),
              ),
            ],
          ] else ...[
            // No relevant matches fallback (F12-07)
            Container(
              padding: const EdgeInsets.all(BuilderSpace.sm),
              decoration: BoxDecoration(
                color: BuilderColors.warningTint,
                borderRadius: BorderRadius.circular(BuilderRadii.tile),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: BuilderColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Ответа в документах нет',
                        style: BuilderTypography.labelMedium.copyWith(
                          color: BuilderColors.warning,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Все фрагменты имеют релевантность ниже порога (35%). Ассистент не фантазирует и честно сообщает об отсутствии информации.',
                    style: BuilderTypography.bodySmall.copyWith(
                      color: BuilderColors.ink,
                    ),
                  ),
                  if (state.generatedAnswer != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Ответ: «${state.generatedAnswer}»',
                      style: BuilderTypography.bodySmall.copyWith(
                        fontStyle: FontStyle.italic,
                        color: BuilderColors.inkSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // View Trace Button (F12-08, F12-10)
          if (state.lastTrace != null) ...[
            const SizedBox(height: BuilderSpace.sm),
            BuilderButton(
              label: 'Смотреть трейс запроса',
              variant: BuilderButtonVariant.secondary,
              onPressed: () {
                TraceSheet.show(context, requestId: state.lastTrace!.requestId);
              },
            ),
          ],
        ],
      ),
    );
  }

  void _handleSearch(KnowledgeNotifier controller) {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    controller.testQueryAndGenerateAnswer(query).then((_) {
      if (mounted) {
        final result = ref
            .read(knowledgeControllerProvider(widget.ownerId))
            .searchResult;
        if (result != null) {
          setState(() {
            if (result.hasRelevantMatches) {
              _testedFound = true;
            } else {
              _testedNotFound = true;
            }
          });

          if (_testedFound &&
              _testedNotFound &&
              widget.onLearningCompleted != null) {
            widget.onLearningCompleted!();
          }
        }
      }
    });
  }

  void _openAddDialog(BuildContext context) {
    D03PersonalDataDialog.show(context, widget.ownerId);
  }

  void _confirmDelete(BuildContext context, KnowledgeDocument doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить документ?'),
        content: Text(
          'Файл «${doc.fileName}» и все созданные фрагменты будут физически удалены с телефона. Исторические версии отметят его как отсутствующий (ADR-02).',
        ),
        actions: [
          TextButton(
            child: const Text('Отмена'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
            onPressed: () {
              Navigator.of(ctx).pop();
              ref
                  .read(knowledgeControllerProvider(widget.ownerId).notifier)
                  .deleteDocument(doc.id);
            },
          ),
        ],
      ),
    );
  }
}
