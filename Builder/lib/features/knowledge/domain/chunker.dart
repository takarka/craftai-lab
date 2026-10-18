import 'knowledge_models.dart';
import 'text_extractor.dart';

/// Sentence-window chunking implementation per F12-05 ('v1.0-sentence-window').
///
/// Chunks extracted document text into stable windows (~300-500 characters)
/// respecting sentence boundaries with a slight overlap (~50-80 chars) to
/// maintain conversational context.
class SentenceWindowChunker {
  final int targetChunkSize;
  final int overlapSize;
  final String strategyVersion;

  const SentenceWindowChunker({
    this.targetChunkSize = 400,
    this.overlapSize = 60,
    this.strategyVersion = 'v1.0-sentence-window',
  });

  /// Chunks an extracted document into a list of [KnowledgeChunk]s.
  List<KnowledgeChunk> chunkDocument({
    required ExtractedDocumentText extracted,
    required String documentId,
    required String revisionId,
    required String ownerId,
    required String documentName,
  }) {
    if (extracted.fullText.trim().isEmpty) {
      return const [];
    }

    final chunks = <KnowledgeChunk>[];
    int globalChunkIndex = 0;
    int cumulativeOffset = 0;

    // Process page by page (or section by section)
    for (int pageIdx = 0; pageIdx < extracted.pages.length; pageIdx++) {
      final pageNum = pageIdx + 1;
      final pageText = extracted.pages[pageIdx].trim();
      if (pageText.isEmpty) continue;

      final pageChunks = _chunkSection(
        sectionText: pageText,
        pageNumber: pageNum,
        baseOffset: cumulativeOffset,
        documentId: documentId,
        revisionId: revisionId,
        ownerId: ownerId,
        documentName: documentName,
        startIndex: globalChunkIndex,
      );

      chunks.addAll(pageChunks);
      globalChunkIndex += pageChunks.length;
      cumulativeOffset += pageText.length + 1;
    }

    return chunks;
  }

  List<KnowledgeChunk> _chunkSection({
    required String sectionText,
    required int pageNumber,
    required int baseOffset,
    required String documentId,
    required String revisionId,
    required String ownerId,
    required String documentName,
    required int startIndex,
  }) {
    final result = <KnowledgeChunk>[];

    // If section fits in a single chunk
    if (sectionText.length <= targetChunkSize) {
      result.add(
        KnowledgeChunk(
          id: '${revisionId}_c$startIndex',
          revisionId: revisionId,
          documentId: documentId,
          documentName: documentName,
          ownerId: ownerId,
          chunkIndex: startIndex,
          chunkText: sectionText,
          pageNumber: pageNumber,
          byteOffset: baseOffset,
          metadata: {
            'strategy': strategyVersion,
            'length': sectionText.length,
            'char_start': baseOffset,
            'char_end': baseOffset + sectionText.length,
          },
        ),
      );
      return result;
    }

    // Split section into sentences
    final sentences = _splitIntoSentences(sectionText);
    if (sentences.isEmpty) return result;

    int chunkIndex = startIndex;
    int currentSentenceStart = 0;

    while (currentSentenceStart < sentences.length) {
      final currentChunkSentences = <String>[];
      int currentLength = 0;
      int windowEnd = currentSentenceStart;

      while (windowEnd < sentences.length) {
        final sentence = sentences[windowEnd];
        if (currentLength + sentence.length > targetChunkSize &&
            currentChunkSentences.isNotEmpty) {
          break;
        }
        currentChunkSentences.add(sentence);
        currentLength += sentence.length;
        windowEnd++;
      }

      final chunkBody = currentChunkSentences.join(' ').trim();
      if (chunkBody.isNotEmpty) {
        // Calculate offset of the first sentence in this chunk
        int sentenceOffsetInSection = 0;
        for (int i = 0; i < currentSentenceStart; i++) {
          sentenceOffsetInSection += sentences[i].length + 1;
        }

        result.add(
          KnowledgeChunk(
            id: '${revisionId}_c$chunkIndex',
            revisionId: revisionId,
            documentId: documentId,
            documentName: documentName,
            ownerId: ownerId,
            chunkIndex: chunkIndex,
            chunkText: chunkBody,
            pageNumber: pageNumber,
            byteOffset: baseOffset + sentenceOffsetInSection,
            metadata: {
              'strategy': strategyVersion,
              'length': chunkBody.length,
              'char_start': baseOffset + sentenceOffsetInSection,
              'char_end':
                  baseOffset + sentenceOffsetInSection + chunkBody.length,
            },
          ),
        );
        chunkIndex++;
      }

      if (windowEnd >= sentences.length) {
        break;
      }

      // Overlap: back up by sentences roughly matching overlapSize
      int backtrackedLength = 0;
      int nextSentenceStart = windowEnd;
      while (nextSentenceStart > currentSentenceStart + 1) {
        final prevSentence = sentences[nextSentenceStart - 1];
        if (backtrackedLength + prevSentence.length > overlapSize) {
          break;
        }
        backtrackedLength += prevSentence.length;
        nextSentenceStart--;
      }

      // Guarantee forward progress
      if (nextSentenceStart <= currentSentenceStart) {
        nextSentenceStart = currentSentenceStart + 1;
      }
      currentSentenceStart = nextSentenceStart;
    }

    return result;
  }

  /// Splits text into sentence fragments based on standard punctuation (. ! ? \n)
  List<String> _splitIntoSentences(String text) {
    final list = <String>[];
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      buffer.write(char);

      if (char == '.' || char == '!' || char == '?' || char == '\n') {
        // Check if this looks like a sentence boundary
        final isLast = i == text.length - 1;
        final nextChar = !isLast ? text[i + 1] : '';

        // If next is whitespace or end of string, finish sentence
        if (isLast ||
            nextChar == ' ' ||
            nextChar == '\n' ||
            nextChar == '\t' ||
            nextChar == '\r') {
          final s = buffer.toString().trim();
          if (s.isNotEmpty) {
            list.add(s);
          }
          buffer.clear();
        }
      }
    }

    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      list.add(remaining);
    }

    return list;
  }
}
