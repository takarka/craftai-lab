import '../../models/infrastructure/craft_ai_client.dart';

class SearchHit {
  final String title;
  final String url;
  final String snippet;
  final String source;

  const SearchHit({
    required this.title,
    required this.url,
    required this.snippet,
    this.source = '',
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'url': url,
    'snippet': snippet,
    'source': source,
  };
}

enum SearchFailureKind {
  /// No signed-in API client.
  notConfigured,

  /// The device could not reach CraftAI.
  noNetwork,

  /// The session expired or the account may not search.
  auth,
  rateLimited,

  /// CraftAI or its search provider failed (5xx).
  unavailable,

  /// The answer did not match the contract.
  invalidResponse,
  cancelled,
}

/// A search that did not produce a result list. An empty list is a success.
class SearchException implements Exception {
  const SearchException(this.kind, [this.message = '']);
  final SearchFailureKind kind;
  final String message;
  @override
  String toString() => 'SearchException(${kind.name}): $message';
}

/// Production search never substitutes educational results for a failed request.
/// Result text comes from the open web: it is cleaned and kept as plain data.
class SearchAdapter {
  final CraftAiClient? client;
  final String language;
  const SearchAdapter({this.client, this.language = 'ru'});

  static const maxTitle = 200;
  static const maxSnippet = 500;
  static const maxUrl = 2000;

  static bool _isHidden(int c) =>
      (c < 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) ||
      c == 0x7F ||
      (c >= 0x200B && c <= 0x200F) || // zero-width and direction marks
      (c >= 0x202A && c <= 0x202E) || // bidi embeddings and overrides
      (c >= 0x2060 && c <= 0x2069) || // word joiner, bidi isolates
      c == 0xFEFF;

  /// Drops control and bidi-override characters, collapses whitespace and
  /// truncates; the result is never interpreted as markup or instructions.
  static String cleanText(String value, int maxLength) {
    final cleaned = String.fromCharCodes(
      value.runes.where((c) => !_isHidden(c)),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= maxLength) return cleaned;
    return '${cleaned.substring(0, maxLength - 1).trimRight()}…';
  }

  /// Only absolute web links without embedded credentials are shown.
  static Uri? safeLink(String url) {
    if (url.length > maxUrl) return null;
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  /// [abortTrigger] completes when the user cancels; the request is aborted.
  Future<List<SearchHit>> search(
    String query, {
    Future<void>? abortTrigger,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed.length > 500) {
      throw ArgumentError('Search query must contain 1–500 characters.');
    }
    final api = client;
    if (api == null) {
      throw const SearchException(
        SearchFailureKind.notConfigured,
        'CraftAI search is not configured.',
      );
    }
    final Map<String, dynamic> data;
    try {
      data = await api.requestJson(
        'POST',
        '/builder/search',
        body: {'query': trimmed, 'language': language, 'limit': 5},
        abortTrigger: abortTrigger,
      );
    } on CraftAiCancelledException {
      throw const SearchException(SearchFailureKind.cancelled);
    } on CraftAiNetworkException catch (error) {
      throw SearchException(SearchFailureKind.noNetwork, error.message);
    } on CraftAiAuthException catch (error) {
      throw SearchException(SearchFailureKind.auth, error.message);
    } on CraftAiForbiddenException catch (error) {
      throw SearchException(SearchFailureKind.auth, error.message);
    } on CraftAiServerException catch (error) {
      throw SearchException(
        switch (error.statusCode) {
          429 => SearchFailureKind.rateLimited,
          final int status when status < 300 => SearchFailureKind.invalidResponse,
          _ => SearchFailureKind.unavailable,
        },
        error.message,
      );
    } on FormatException catch (error) {
      throw SearchException(SearchFailureKind.invalidResponse, error.message);
    }

    try {
      final seen = <String>{};
      final hits = <SearchHit>[];
      for (final value in data['results'] as List<dynamic>) {
        final item = value as Map<String, dynamic>;
        final uri = safeLink(item['url'] as String);
        final title = cleanText(item['title'] as String, maxTitle);
        if (uri == null || title.isEmpty || !seen.add(uri.toString())) {
          continue;
        }
        hits.add(
          SearchHit(
            title: title,
            url: uri.toString(),
            snippet: cleanText(item['snippet'] as String? ?? '', maxSnippet),
            source: cleanText(
              item['source'] as String? ?? data['source'] as String? ?? uri.host,
              100,
            ),
          ),
        );
      }
      return hits;
    } on TypeError {
      throw const SearchException(
        SearchFailureKind.invalidResponse,
        'Unexpected search response shape.',
      );
    }
  }
}
