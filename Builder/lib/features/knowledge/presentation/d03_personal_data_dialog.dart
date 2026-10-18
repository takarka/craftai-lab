import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui_kit/controls.dart';
import '../../../ui_kit/identity.dart';
import '../../../ui_kit/tokens.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_providers.dart';

/// D03 Privacy Dialog & Document Importer (F12-01, F12-V01).
///
/// Explicitly warns about student personal data before import.
/// Validates formats (PDF, DOCX, TXT only; no XLSX) and provides educational presets
/// for reliable offline testing and learning.
class D03PersonalDataDialog extends ConsumerStatefulWidget {
  final String ownerId;

  const D03PersonalDataDialog({
    super.key,
    required this.ownerId,
  });

  static Future<KnowledgeDocument?> show(BuildContext context, String ownerId) {
    return showModalBottomSheet<KnowledgeDocument>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => D03PersonalDataDialog(ownerId: ownerId),
    );
  }

  @override
  ConsumerState<D03PersonalDataDialog> createState() => _D03PersonalDataDialogState();
}

class _D03PersonalDataDialogState extends ConsumerState<D03PersonalDataDialog> {
  String? _selectedSampleKey;
  String? _customFileName;
  Uint8List? _customBytes;
  DocumentFormat? _customFormat;
  String? _validationError;

  // Educational sample presets for offline use & testing
  static const _samplePresets = <String, _SampleDoc>{
    'timetable': _SampleDoc(
      fileName: 'Расписание_7Б.docx',
      format: DocumentFormat.docx,
      title: 'Расписание уроков 7 «Б» класса',
      subtitle: 'DOCX · 12 КБ · Учебный план на четверть',
      content: 'Расписание уроков 7 «Б» класса на вторую четверть.\n'
          'Понедельник: 1. Алгебра (кабинет 24), 2. Физика (кабинет 18), 3. Биология (кабинет 12), 4. История.\n'
          'Вторник: 1. Русский язык, 2. Литература, 3. География, 4. Физкультура.\n'
          'Среда: 1. Геометрия, 2. Английский язык, 3. Информатика (кабинет 30), 4. Обществознание.\n'
          'Четверг: 1. Алгебра, 2. Химия, 3. Музыка, 4. Литература.\n'
          'Пятница: 1. Физика, 2. Русский язык, 3. Биология, 4. Классный час.',
    ),
    'biology': _SampleDoc(
      fileName: 'Биология_программа.pdf',
      format: DocumentFormat.pdf,
      title: 'Учебная программа по биологии (7 класс)',
      subtitle: 'PDF · 45 КБ · Тематическое планирование',
      content: 'Рабочая программа по биологии для 7 класса.\n'
          'Тема 1: Строение растительной и животной клетки. Органоиды, клеточная мембрана и хлоропласты.\n'
          'Лабораторная работа №3: Изучение микропрепарата кожицы лука под микроскопом. Требуется подготовить предметные стекла и раствор йода.\n'
          'Контрольная работа по теме «Клетка и ткани» запланирована на 25 ноября.',
    ),
    'safety': _SampleDoc(
      fileName: 'Памятка_учителя.txt',
      format: DocumentFormat.txt,
      title: 'Памятка по технике безопасности в кабинете',
      subtitle: 'TXT · 4 КБ · Инструкция по дежурству',
      content: 'Памятка дежурного преподавателя.\n'
          '1. Проветривание кабинета проводится на каждой перемене не менее 10 минут в отсутствие учеников.\n'
          '2. В кабинетах химии и физики реактивы и приборы хранятся исключительно в закрытом лаборантском шкафу.\n'
          '3. В случае задымления или аварийной ситуации немедленно нажать тревожную кнопку у выхода и организовать эвакуацию по схеме Б.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(knowledgeControllerProvider(widget.ownerId));

    return Container(
      decoration: const BoxDecoration(
        color: BuilderColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(BuilderRadii.sheet)),
      ),
      padding: EdgeInsets.only(
        left: BuilderSpace.md,
        right: BuilderSpace.md,
        top: BuilderSpace.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + BuilderSpace.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: BuilderColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: BuilderSpace.md),

            // Header
            Row(
              children: [
                const BuilderIcon(BuilderGlyph.doc, size: 24, color: BuilderColors.primary),
                const SizedBox(width: BuilderSpace.xs),
                Expanded(
                  child: Text(
                    'Добавление документа',
                    style: BuilderTypography.titleMedium.copyWith(color: BuilderColors.ink),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: BuilderColors.inkSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: BuilderSpace.sm),

            // Privacy warning banner per D03 / F12-01
            Container(
              padding: const EdgeInsets.all(BuilderSpace.sm),
              decoration: BoxDecoration(
                color: BuilderColors.warningTint,
                borderRadius: BorderRadius.circular(BuilderRadii.tile),
                border: Border.all(color: BuilderColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: BuilderIcon(BuilderGlyph.info, size: 20, color: BuilderColors.warning),
                  ),
                  const SizedBox(width: BuilderSpace.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Защита персональных данных учеников',
                          style: BuilderTypography.labelMedium.copyWith(
                            color: BuilderColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Не загружайте документы с ФИО, оценками, медицинскими данными или контактами учащихся. Исходные файлы хранятся только на этом телефоне, но найденные фрагменты передаются модели для генерации ответа.',
                          style: BuilderTypography.bodySmall.copyWith(
                            color: BuilderColors.ink,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: BuilderSpace.md),

            // Supported formats info
            Text(
              'Поддерживаются: PDF, DOCX, TXT (до 10 МБ).',
              style: BuilderTypography.bodySmall.copyWith(color: BuilderColors.inkSecondary),
            ),
            Text(
              'Таблицы Excel (.xlsx) не поддерживаются.',
              style: BuilderTypography.bodySmall.copyWith(
                color: BuilderColors.inkDisabled,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: BuilderSpace.md),

            if (_validationError != null) ...[
              Container(
                padding: const EdgeInsets.all(BuilderSpace.xs),
                margin: const EdgeInsets.only(bottom: BuilderSpace.sm),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(BuilderRadii.control),
                ),
                child: Text(
                  _validationError!,
                  style: BuilderTypography.bodySmall.copyWith(color: Colors.red.shade800),
                ),
              ),
            ],

            Text(
              'Выберите учебный документ:',
              style: BuilderTypography.labelMedium.copyWith(color: BuilderColors.inkSecondary),
            ),
            const SizedBox(height: BuilderSpace.xs),

            // Educational sample documents
            ..._samplePresets.entries.map((entry) {
              final isSelected = _selectedSampleKey == entry.key;
              final sample = entry.value;

              return Padding(
                padding: const EdgeInsets.only(bottom: BuilderSpace.xs),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedSampleKey = entry.key;
                      _customFileName = null;
                      _customBytes = null;
                      _validationError = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(BuilderRadii.tile),
                  child: Container(
                    padding: const EdgeInsets.all(BuilderSpace.sm),
                    decoration: BoxDecoration(
                      color: isSelected ? BuilderColors.primaryTint : BuilderColors.surface,
                      borderRadius: BorderRadius.circular(BuilderRadii.tile),
                      border: Border.all(
                        color: isSelected ? BuilderColors.primary : BuilderColors.line,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        _FormatBadge(format: sample.format),
                        const SizedBox(width: BuilderSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sample.title,
                                style: BuilderTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: BuilderColors.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                sample.subtitle,
                                style: BuilderTypography.bodySmall.copyWith(
                                  color: BuilderColors.inkSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle, color: BuilderColors.primary, size: 20),
                      ],
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: BuilderSpace.md),

            // Submit Button
            BuilderButton(
              label: state.isImporting ? 'Индексация документа...' : 'Импортировать в базу знаний',
              loading: state.isImporting,
              onPressed: (_selectedSampleKey == null && _customBytes == null)
                  ? null
                  : _handleImport,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleImport() async {
    setState(() => _validationError = null);
    final controller = ref.read(knowledgeControllerProvider(widget.ownerId).notifier);

    String fileName;
    Uint8List bytes;
    DocumentFormat format;

    if (_selectedSampleKey != null) {
      final sample = _samplePresets[_selectedSampleKey]!;
      fileName = sample.fileName;
      format = sample.format;

      if (format == DocumentFormat.docx) {
        // Construct minimal valid DOCX with word/document.xml
        bytes = _createMockDocxBytes(sample.content);
      } else if (format == DocumentFormat.pdf) {
        // Construct minimal valid PDF with /Type /Page and BT/ET
        bytes = _createMockPdfBytes(sample.content);
      } else {
        bytes = Uint8List.fromList(utf8.encode(sample.content));
      }
    } else if (_customBytes != null && _customFileName != null && _customFormat != null) {
      fileName = _customFileName!;
      bytes = _customBytes!;
      format = _customFormat!;
    } else {
      return;
    }

    final doc = await controller.importDocument(
      fileName: fileName,
      bytes: bytes,
      format: format,
    );

    if (!mounted) return;
    if (doc != null) {
      Navigator.pop(context, doc);
    } else {
      final err = ref.read(knowledgeControllerProvider(widget.ownerId)).errorMessage;
      setState(() => _validationError = err ?? 'Не удалось импортировать документ');
    }
  }

  Uint8List _createMockDocxBytes(String text) {
    // Escape XML entities
    final escapedText = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r>
        <w:t>$escapedText</w:t>
      </w:r>
    </w:p>
  </w:body>
</w:document>''';

    // Zip archive with word/document.xml
    final archive = Archive();
    final bytes = utf8.encode(documentXml);
    archive.addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Uint8List _createMockPdfBytes(String text) {
    // Generate valid minimal PDF structure
    final cleanText = text.replaceAll('(', '[').replaceAll(')', ']');
    final pdfContent = '%PDF-1.4\n'
        '1 0 obj\n'
        '<< /Type /Catalog /Pages 2 0 R >>\n'
        'endobj\n'
        '2 0 obj\n'
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>\n'
        'endobj\n'
        '3 0 obj\n'
        '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\n'
        'endobj\n'
        '4 0 obj\n'
        '<< /Length ${cleanText.length + 20} >>\n'
        'stream\n'
        'BT\n'
        '/F1 12 Tf\n'
        '($cleanText) Tj\n'
        'ET\n'
        'endstream\n'
        'endobj\n'
        'xref\n'
        '0 5\n'
        '0000000000 65535 f \n'
        'trailer\n'
        '<< /Root 1 0 R >>\n'
        '%%EOF';
    return Uint8List.fromList(utf8.encode(pdfContent));
  }
}

class _FormatBadge extends StatelessWidget {
  final DocumentFormat format;

  const _FormatBadge({required this.format});

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BuilderRadii.chip),
      ),
      child: Text(
        format.label,
        style: BuilderTypography.labelSmall.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _SampleDoc {
  final String fileName;
  final DocumentFormat format;
  final String title;
  final String subtitle;
  final String content;

  const _SampleDoc({
    required this.fileName,
    required this.format,
    required this.title,
    required this.subtitle,
    required this.content,
  });
}
