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

/// Production search never substitutes educational results for a failed request.
class SearchAdapter {
  final CraftAiClient? client;
  final String language;
  const SearchAdapter({this.client, this.language = 'ru'});

  Future<List<SearchHit>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed.length > 500) {
      throw ArgumentError('Search query must contain 1–500 characters.');
    }
    final api = client;
    if (api == null) {
      throw const CraftAiNetworkException('CraftAI search is not configured.');
    }
    final data = await api.requestJson(
      'POST',
      '/builder/search',
      body: {'query': trimmed, 'language': language, 'limit': 5},
    );
    final items = data['results'] as List<dynamic>;
    return items.map((value) {
      final item = value as Map<String, dynamic>;
      final url = item['url'] as String;
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw const FormatException('Invalid search result URL.');
      }
      return SearchHit(
        title: item['title'] as String,
        url: url,
        snippet: item['snippet'] as String,
        source: item['source'] as String? ?? data['source'] as String? ?? '',
      );
    }).toList();
  }
}
