import 'dart:math' as math;
import 'knowledge_models.dart';

/// On-device deterministic hybrid embedding and search engine (F12-06, F12-07).
///
/// Combines subword/character n-gram semantic vector representation with
/// lexical token overlap. Runs entirely in Dart on-device without network calls
/// or external C++ dependencies.
class LocalHybridSearchEngine {
  static const int vectorDimensions = 96;
  static const double defaultRelevanceThreshold = 0.35;

  final double relevanceThreshold;
  final int topK;

  const LocalHybridSearchEngine({
    this.relevanceThreshold = defaultRelevanceThreshold,
    this.topK = 3,
  });

  /// Generates a normalized dense vector for [text]
  List<double> embedText(String text) {
    if (text.trim().isEmpty) {
      return List.filled(vectorDimensions, 0.0);
    }

    final vector = List.filled(vectorDimensions, 0.0);
    final normalized = _normalizeText(text);

    // 1. Word tokens with sublinear frequency
    final words = normalized.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    final wordFrequencies = <String, int>{};
    for (final w in words) {
      wordFrequencies[w] = (wordFrequencies[w] ?? 0) + 1;
    }

    for (final entry in wordFrequencies.entries) {
      final word = entry.key;
      final weight = 1.0 + math.log(entry.value);
      _hashIntoVector(word, weight, vector);

      // Subword character trigrams
      if (word.length >= 3) {
        for (int i = 0; i <= word.length - 3; i++) {
          final trigram = word.substring(i, i + 3);
          _hashIntoVector(trigram, weight * 0.5, vector);
        }
      }
    }

    // 2. L2 Normalization
    double norm = 0.0;
    for (int i = 0; i < vectorDimensions; i++) {
      norm += vector[i] * vector[i];
    }
    norm = math.sqrt(norm);

    if (norm > 0) {
      for (int i = 0; i < vectorDimensions; i++) {
        vector[i] = vector[i] / norm;
      }
    }

    return vector;
  }

  /// Calculates cosine similarity between two normalized vectors
  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot.clamp(0.0, 1.0);
  }

  /// Calculates lexical match ratio of query words in candidate text
  double lexicalScore(String query, String chunkText) {
    final normQuery = _normalizeText(query);
    final normChunk = _normalizeText(chunkText);

    final queryWords = normQuery.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    if (queryWords.isEmpty) {
      // Query has only very short words or characters
      return normChunk.contains(normQuery) ? 0.8 : 0.0;
    }

    int matchedCount = 0;
    for (final qw in queryWords) {
      if (normChunk.contains(qw)) {
        matchedCount++;
      }
    }

    return matchedCount / queryWords.length;
  }

  /// Searches a collection of chunks for the given [query]
  KnowledgeSearchResult search({
    required String query,
    required List<KnowledgeChunk> chunks,
    double? thresholdOverride,
  }) {
    final stopwatch = Stopwatch()..start();
    final effectiveThreshold = thresholdOverride ?? relevanceThreshold;

    if (query.trim().isEmpty || chunks.isEmpty) {
      stopwatch.stop();
      return KnowledgeSearchResult(
        query: query,
        matches: const [],
        hasRelevantMatches: false,
        totalScannedChunks: chunks.length,
        searchDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    final queryVector = embedText(query);
    final scoredList = <SearchResultChunk>[];

    for (final chunk in chunks) {
      // Get or compute chunk embedding
      List<double> chunkVec = chunk.embeddingVector;
      if (chunkVec.isEmpty || chunkVec.length != vectorDimensions) {
        chunkVec = embedText(chunk.chunkText);
      }

      final semanticSim = cosineSimilarity(queryVector, chunkVec);
      final lexSim = lexicalScore(query, chunk.chunkText);

      // Hybrid combination (60% semantic, 40% lexical)
      final rawScore = (semanticSim * 0.55) + (lexSim * 0.45);
      final score = rawScore.clamp(0.0, 1.0);
      final isAbove = score >= effectiveThreshold;

      scoredList.add(SearchResultChunk(
        chunk: chunk,
        score: score,
        isAboveThreshold: isAbove,
      ));
    }

    // Sort descending by score
    scoredList.sort((a, b) => b.score.compareTo(a.score));

    final topMatches = scoredList.take(topK).toList();
    final hasRelevant = topMatches.any((m) => m.isAboveThreshold);

    stopwatch.stop();

    return KnowledgeSearchResult(
      query: query,
      matches: topMatches,
      hasRelevantMatches: hasRelevant,
      totalScannedChunks: chunks.length,
      searchDurationMs: stopwatch.elapsedMilliseconds,
    );
  }

  void _hashIntoVector(String token, double weight, List<double> vector) {
    int h1 = 0x811c9dc5;
    for (int i = 0; i < token.length; i++) {
      h1 ^= token.codeUnitAt(i);
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF;
    }

    final index = (h1.abs()) % vectorDimensions;
    final sign = ((h1 >> 8) & 1) == 0 ? 1.0 : -1.0;
    vector[index] += sign * weight;
  }

  String _normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\sа-яёА-ЯЁ0-9]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
