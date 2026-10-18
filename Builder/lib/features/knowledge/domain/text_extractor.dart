import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import 'knowledge_models.dart';

class DocumentProcessingException implements Exception {
  final String code;
  final String message;

  const DocumentProcessingException({required this.code, required this.message});

  @override
  String toString() => 'DocumentProcessingException($code): $message';
}

class ExtractedDocumentText {
  final String fullText;
  final List<String> pages; // 1-indexed pages or sections
  final int totalCharacters;

  const ExtractedDocumentText({
    required this.fullText,
    required this.pages,
    required this.totalCharacters,
  });
}

class TextExtractor {
  const TextExtractor();

  /// Asynchronous extraction entrypoint suitable for calling inside `compute`
  static Future<ExtractedDocumentText> extract({
    required Uint8List bytes,
    required DocumentFormat format,
    required String fileName,
  }) async {
    return compute(_extractIsolateWorker, _ExtractJob(bytes: bytes, format: format, fileName: fileName));
  }

  static ExtractedDocumentText _extractIsolateWorker(_ExtractJob job) {
    switch (job.format) {
      case DocumentFormat.txt:
        return _extractTxt(job.bytes);
      case DocumentFormat.docx:
        return _extractDocx(job.bytes);
      case DocumentFormat.pdf:
        return _extractPdf(job.bytes);
    }
  }

  // --------------------------------------------------------------------------
  // TXT Extractor
  // --------------------------------------------------------------------------
  static ExtractedDocumentText _extractTxt(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const DocumentProcessingException(
        code: 'empty_text',
        message: 'Файл пуст',
      );
    }

    String decoded;
    try {
      // Try UTF-8
      decoded = utf8.decode(bytes);
    } catch (_) {
      try {
        // Fallback: Latin1 / Windows-1251 compatible stream
        decoded = latin1.decode(bytes);
      } catch (e) {
        throw DocumentProcessingException(
          code: 'corrupt_file',
          message: 'Не удалось определить кодировку текста: $e',
        );
      }
    }

    final trimmed = decoded.trim();
    if (trimmed.isEmpty) {
      throw const DocumentProcessingException(
        code: 'empty_text',
        message: 'Документ не содержит распознаваемого текста',
      );
    }

    // Split into pages by form feed (\f) or by ~2000 char sections
    final pages = _splitIntoSections(trimmed);
    return ExtractedDocumentText(
      fullText: trimmed,
      pages: pages,
      totalCharacters: trimmed.length,
    );
  }

  // --------------------------------------------------------------------------
  // DOCX Extractor (F12-04: safe unzip, ignores macros, active content & links)
  // --------------------------------------------------------------------------
  static ExtractedDocumentText _extractDocx(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const DocumentProcessingException(code: 'empty_text', message: 'Файл пуст');
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (e) {
      throw DocumentProcessingException(
        code: 'corrupt_file',
        message: 'Некорректный или повреждённый DOCX-архив: $e',
      );
    }

    // 1. Locate word/document.xml
    ArchiveFile? documentXmlFile;
    for (final file in archive.files) {
      if (file.name == 'word/document.xml') {
        documentXmlFile = file;
        break;
      }
    }

    if (documentXmlFile == null) {
      throw const DocumentProcessingException(
        code: 'corrupt_file',
        message: 'Файл не является корректным документом DOCX (отсутствует word/document.xml)',
      );
    }

    // 2. Decode and parse XML, strictly extracting text nodes <w:t>
    String xmlContent;
    try {
      final rawBytes = documentXmlFile.content as List<int>;
      xmlContent = utf8.decode(rawBytes);
    } catch (e) {
      throw DocumentProcessingException(
        code: 'corrupt_file',
        message: 'Ошибка декодирования содержимого DOCX: $e',
      );
    }

    XmlDocument document;
    try {
      document = XmlDocument.parse(xmlContent);
    } catch (e) {
      throw DocumentProcessingException(
        code: 'corrupt_file',
        message: 'Ошибка структуры XML в DOCX: $e',
      );
    }

    // 3. Extract text paragraphs
    final buffer = StringBuffer();
    final paragraphs = document.findAllElements('w:p');

    for (final p in paragraphs) {
      final pBuffer = StringBuffer();
      for (final t in p.findAllElements('w:t')) {
        pBuffer.write(t.innerText);
      }
      final paragraphText = pBuffer.toString().trim();
      if (paragraphText.isNotEmpty) {
        buffer.writeln(paragraphText);
      }
    }

    final fullText = buffer.toString().trim();
    if (fullText.isEmpty) {
      throw const DocumentProcessingException(
        code: 'empty_text',
        message: 'В документе DOCX не найден текстовый контент',
      );
    }

    final pages = _splitIntoSections(fullText);
    return ExtractedDocumentText(
      fullText: fullText,
      pages: pages,
      totalCharacters: fullText.length,
    );
  }

  // --------------------------------------------------------------------------
  // PDF Extractor (F12-03: handles password, scans without text, corruption)
  // --------------------------------------------------------------------------
  static ExtractedDocumentText _extractPdf(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const DocumentProcessingException(code: 'empty_text', message: 'Файл пуст');
    }

    // Validate PDF header %PDF-
    final headerStr = String.fromCharCodes(bytes.take(8));
    if (!headerStr.contains('%PDF-')) {
      throw const DocumentProcessingException(
        code: 'corrupt_file',
        message: 'Файл не содержит корректного заголовка PDF',
      );
    }

    final rawString = latin1.decode(bytes);

    // 1. Password check: /Encrypt dictionary
    if (rawString.contains('/Encrypt')) {
      throw const DocumentProcessingException(
        code: 'password_protected',
        message: 'Документ защищен паролем. Снимите защиту для добавления в знания.',
      );
    }

    // 2. Extract text streams and direct text operators (Tj, TJ, BT...ET)
    final buffer = StringBuffer();
    final pages = <String>[];

    // Split roughly by /Page objects or text blocks
    final pagePattern = RegExp(r'/Type\s*/Page\b');
    final hasPageMarkers = pagePattern.hasMatch(rawString);

    // Extract text from text blocks BT ... ET
    final btPattern = RegExp(r'BT\s*(.*?)\s*ET', dotAll: true);
    final btMatches = btPattern.allMatches(rawString);

    for (final match in btMatches) {
      final block = match.group(1) ?? '';
      final textFromBlock = _parsePdfTextBlock(block);
      if (textFromBlock.isNotEmpty) {
        buffer.writeln(textFromBlock);
      }
    }

    // Also look for FlateDecode streams that might contain compressed text
    if (buffer.isEmpty) {
      _extractFromPdfStreams(bytes, buffer);
    }

    final fullText = buffer.toString().trim();

    // 3. Scan check: if PDF has pages/images but 0 extractable characters
    if (fullText.isEmpty) {
      if (rawString.contains('/Image') || rawString.contains('/Subtype /Image') || hasPageMarkers) {
        throw const DocumentProcessingException(
          code: 'scanned_image_no_text',
          message: 'Документ содержит изображение/скан без текстового слоя. Требуется распознавание текста (OCR).',
        );
      }
      throw const DocumentProcessingException(
        code: 'empty_text',
        message: 'В документе PDF не найден текстовый слой',
      );
    }

    pages.addAll(_splitIntoSections(fullText));

    return ExtractedDocumentText(
      fullText: fullText,
      pages: pages,
      totalCharacters: fullText.length,
    );
  }

  static String _parsePdfTextBlock(String block) {
    final sb = StringBuffer();

    // Extract (text) Tj
    final tjPattern = RegExp(r'\((.*?)\)\s*Tj');
    for (final m in tjPattern.allMatches(block)) {
      final t = m.group(1);
      if (t != null && t.isNotEmpty) {
        sb.write(_decodePdfString(t));
        sb.write(' ');
      }
    }

    // Extract [(text) (text)] TJ
    final arrayTjPattern = RegExp(r'\[(.*?)\]\s*TJ');
    for (final m in arrayTjPattern.allMatches(block)) {
      final arrayContent = m.group(1) ?? '';
      final innerTextPattern = RegExp(r'\((.*?)\)');
      for (final tm in innerTextPattern.allMatches(arrayContent)) {
        final t = tm.group(1);
        if (t != null && t.isNotEmpty) {
          sb.write(_decodePdfString(t));
        }
      }
      sb.write(' ');
    }

    return sb.toString().trim();
  }

  static String _decodePdfString(String raw) {
    final unescaped = _unescapePdfText(raw);
    try {
      final codeUnits = unescaped.codeUnits;
      if (codeUnits.any((u) => u > 127)) {
        final bytes = Uint8List.fromList(codeUnits);
        final decoded = utf8.decode(bytes, allowMalformed: true);
        if (decoded.isNotEmpty) return decoded;
      }
    } catch (_) {}
    return unescaped;
  }

  static String _unescapePdfText(String raw) {
    return raw
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\\', '\\');
  }

  static void _extractFromPdfStreams(Uint8List bytes, StringBuffer output) {
    final raw = latin1.decode(bytes);
    final streamPattern = RegExp(r'stream[\r\n]+(.*?)[\r\n]+endstream', dotAll: true);

    for (final m in streamPattern.allMatches(raw)) {
      final streamContent = m.group(1);
      if (streamContent == null) continue;

      try {
        final streamBytes = Uint8List.fromList(streamContent.codeUnits);
        // Try decompressing via zlib/flate
        final decompressed = ZLibDecoder().decodeBytes(streamBytes, verify: false);
        final decodedStr = latin1.decode(decompressed);

        if (decodedStr.contains('BT') && decodedStr.contains('ET')) {
          final text = _parsePdfTextBlock(decodedStr);
          if (text.isNotEmpty) {
            output.writeln(text);
          }
        }
      } catch (_) {
        // Not a compressed stream or different compression algorithm
      }
    }
  }

  static List<String> _splitIntoSections(String text, {int sectionSize = 1500}) {
    if (text.length <= sectionSize) return [text];
    final sections = <String>[];
    int start = 0;
    while (start < text.length) {
      int end = start + sectionSize;
      if (end >= text.length) {
        sections.add(text.substring(start));
        break;
      }
      // Break on paragraph or space
      final nextNewline = text.indexOf('\n', end - 200);
      if (nextNewline != -1 && nextNewline < end + 200 && nextNewline < text.length) {
        end = nextNewline;
      }
      sections.add(text.substring(start, end).trim());
      start = end;
    }
    return sections;
  }
}

class _ExtractJob {
  final Uint8List bytes;
  final DocumentFormat format;
  final String fileName;

  const _ExtractJob({
    required this.bytes,
    required this.format,
    required this.fileName,
  });
}
