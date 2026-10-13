import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class SearchResult {
  final String title;
  final String snippet;
  final String? url;

  const SearchResult({
    required this.title,
    required this.snippet,
    this.url,
  });
}

class WebSearchService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
      },
    ),
  );

  final RegExp _urlRegex = RegExp(
    r'(https?:\/\/[^\s]+)',
    caseSensitive: false,
  );

  String _cleanUrl(String raw) {
    var url = raw.trim();
    const trailingChars = {'»', '"', "'", '.', ',', ';', ':', '?', '!', ')', ']', '>'};
    while (url.isNotEmpty && trailingChars.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1).trim();
    }
    return url;
  }

  bool containsUrl(String text) => extractUrls(text).isNotEmpty;

  List<String> extractUrls(String text) {
    return _urlRegex
        .allMatches(text)
        .map((m) => _cleanUrl(m.group(0)!))
        .where((u) => u.isNotEmpty)
        .toList();
  }

  /// Fetches content from a URL directly
  Future<String?> fetchWebPageText(String url) async {
    try {
      final response = await _dio.get<String>(url);
      if (response.data == null) return null;

      final html = response.data!;
      // Clean HTML tags and scripts
      String cleaned = html
          .replaceAll(RegExp(r'<script\b[^>-]*>([\s\S]*?)<\/script>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<style\b[^>-]*>([\s\S]*?)<\/style>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (cleaned.length > 2500) {
        cleaned = '${cleaned.substring(0, 2500)}...';
      }
      return cleaned;
    } catch (e) {
      debugPrint('[WEB SEARCH] Error fetching URL $url: $e');
      return null;
    }
  }

  /// Searches the web using DuckDuckGo Instant Answers & Wikipedia APIs
  Future<List<SearchResult>> search(String query) async {
    final results = <SearchResult>[];

    // 1. Try DuckDuckGo Instant Answer API
    try {
      final ddgUrl =
          'https://api.duckduckgo.com/?q=${Uri.encodeComponent(query)}&format=json&no_html=1&skip_disambig=1';
      final response = await _dio.get<String>(ddgUrl);
      if (response.data != null && response.data!.isNotEmpty) {
        final data = jsonDecode(response.data!);
        final abstractText = data['AbstractText'] as String?;
        final heading = data['Heading'] as String?;
        final abstractUrl = data['AbstractURL'] as String?;

        if (abstractText != null && abstractText.isNotEmpty) {
          results.add(
            SearchResult(
              title: heading ?? 'DuckDuckGo Summary',
              snippet: abstractText,
              url: abstractUrl,
            ),
          );
        }

        final relatedTopics = data['RelatedTopics'] as List?;
        if (relatedTopics != null) {
          for (final item in relatedTopics.take(3)) {
            if (item is Map && item.containsKey('Text')) {
              results.add(
                SearchResult(
                  title: 'Информация',
                  snippet: item['Text'] as String,
                  url: item['FirstURL'] as String?,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[WEB SEARCH] DuckDuckGo API error: $e');
    }

    // 2. Try Russian Wikipedia API for knowledge queries
    try {
      final wikiUrl =
          'https://ru.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(query)}&format=json&utf8=1&srlimit=3';
      final response = await _dio.get<Map<String, dynamic>>(wikiUrl);
      if (response.data != null) {
        final queryData = response.data!['query'] as Map<String, dynamic>?;
        final searchList = queryData?['search'] as List?;

        if (searchList != null) {
          for (final item in searchList.take(2)) {
            final title = item['title'] as String;
            final snippetRaw = item['snippet'] as String;
            final snippet = snippetRaw.replaceAll(RegExp(r'<[^>]*>'), '');
            results.add(
              SearchResult(
                title: 'Wikipedia: $title',
                snippet: snippet,
                url: 'https://ru.wikipedia.org/wiki/${Uri.encodeComponent(title)}',
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[WEB SEARCH] Wikipedia API error: $e');
    }

    return results;
  }

  /// Builds context string for model from search results or URLs
  Future<String?> getWebContext(String userPrompt) async {
    // If user provided a URL, read it
    if (containsUrl(userPrompt)) {
      final urls = extractUrls(userPrompt);
      final firstUrl = urls.first;
      final pageText = await fetchWebPageText(firstUrl);
      if (pageText != null && pageText.isNotEmpty) {
        return '=== СОДЕРЖИМОЕ СТРАНИЦЫ ($firstUrl) ===\n$pageText\n=== КОНЕЦ СОДЕРЖИМОГО ===';
      }
    }

    // Otherwise, perform search
    final results = await search(userPrompt);
    if (results.isEmpty) return null;

    final buffer = StringBuffer();
    buffer.writeln('=== АКТУАЛЬНЫЕ ДАННЫЕ ИЗ ИНТЕРНЕТА ===');
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('${i + 1}. [${r.title}]');
      buffer.writeln('   ${r.snippet}');
      if (r.url != null && r.url!.isNotEmpty) {
        buffer.writeln('   Источник: ${r.url}');
      }
      buffer.writeln();
    }
    buffer.writeln('=== КОНЕЦ ДАННЫХ ИЗ ИНТЕРНЕТА ===');
    return buffer.toString();
  }
}
