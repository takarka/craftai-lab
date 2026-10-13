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
      connectTimeout: const Duration(seconds: 7),
      receiveTimeout: const Duration(seconds: 9),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'ru-RU,ru;q=0.9,kk-KZ;q=0.8,kk;q=0.7,en-US;q=0.6,en;q=0.5',
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
      debugPrint('[WEB SEARCH] Ошибка загрузки URL $url: $e');
      return null;
    }
  }

  /// Checks if query is weather-related (in RU, KK, or EN)
  bool isWeatherQuery(String query) {
    final lower = query.toLowerCase();
    final weatherPatterns = [
      'погода',
      'погоду',
      'погоде',
      'температур',
      'прогноз',
      'градус',
      'осадк',
      'дожд',
      'снег',
      'ауа рай',
      'ауа-рай',
      'жауын',
      'жаңбыр',
      'weather',
      'forecast',
      'temperature',
    ];
    return weatherPatterns.any((p) => lower.contains(p));
  }

  /// Extracts probable city name from query
  String extractCity(String query) {
    final lower = query.toLowerCase();

    // 1. Direct city dictionary check (KZ, CIS, World)
    final cityMap = {
      'астана': 'Астана',
      'astana': 'Astana',
      'нур-султан': 'Астана',
      'алматы': 'Алматы',
      'almaty': 'Almaty',
      'шымкент': 'Шымкент',
      'караганд': 'Караганда',
      'қарағанд': 'Қарағанды',
      'актобе': 'Актобе',
      'ақтөбе': 'Ақтөбе',
      'тараз': 'Тараз',
      'павлодар': 'Павлодар',
      'усть-каменогорск': 'Усть-Каменогорск',
      'өскемен': 'Өскемен',
      'семей': 'Семей',
      'костанай': 'Костанай',
      'қостанай': 'Қостанай',
      'атырау': 'Атырау',
      'актау': 'Актау',
      'ақтау': 'Ақтау',
      'кызылорд': 'Кызылорда',
      'қызылорд': 'Қызылорда',
      'уральск': 'Уральск',
      'орал': 'Орал',
      'петропавл': 'Петропавловск',
      'москв': 'Москва',
      'питер': 'Санкт-Петербург',
      'санкт-петербург': 'Санкт-Петербург',
      'ташкент': 'Ташкент',
      'бишкек': 'Бишкек',
      'дубай': 'Дубай',
      'дубаи': 'Дубай',
      'лондон': 'Лондон',
      'париж': 'Париж',
      'нью-йорк': 'Нью-Йорк',
      'токио': 'Токио',
      'пекин': 'Пекин',
      'стамбул': 'Стамбул',
      'анталья': 'Анталья',
    };

    for (final entry in cityMap.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }

    // 2. Kazakh locative case extraction (e.g. "Астанада", "Алматыда", "Семейде")
    final kzMatch = RegExp(r'([А-ЯЁа-яёӘәҒғҚқҢңӨөҰұҮүҺһІіA-Za-z]{3,})(?:да|де|та|те|нда|нде)\b')
        .firstMatch(query);
    if (kzMatch != null) {
      final potentialCity = kzMatch.group(1)!;
      if (!isWeatherQuery(potentialCity)) {
        return potentialCity;
      }
    }

    // 3. Russian preposition extraction ("в Астане", "в Москве", "по городу Алматы")
    final ruMatch = RegExp(r'(?:в|во|по|городе|г\.)\s+([А-ЯЁа-яёA-Za-z\-]{3,})', caseSensitive: false)
        .firstMatch(query);
    if (ruMatch != null) {
      final cityCandidate = ruMatch.group(1)!;
      if (!isWeatherQuery(cityCandidate)) {
        return cityCandidate;
      }
    }

    // Default fallback if no city recognized in weather prompt
    return 'Астана';
  }

  /// Fetches real-time weather from wttr.in
  Future<String?> fetchWeather(String city) async {
    try {
      debugPrint('[WEATHER] Запрос погоды для города: $city');
      final encoded = Uri.encodeComponent(city);
      final url = 'https://wttr.in/$encoded?format=j1&lang=ru';
      final response = await _dio.get<dynamic>(url);

      if (response.data != null) {
        Map<String, dynamic> data;
        if (response.data is String) {
          data = jsonDecode(response.data as String) as Map<String, dynamic>;
        } else {
          data = response.data as Map<String, dynamic>;
        }

        final currentList = data['current_condition'] as List?;
        if (currentList != null && currentList.isNotEmpty) {
          final current = currentList.first as Map<String, dynamic>;
          final tempC = current['temp_C'] ?? '?';
          final feelsLikeC = current['FeelsLikeC'] ?? tempC;
          final humidity = current['humidity'] ?? '?';
          final windKmh = current['windspeedKmph'] ?? '?';

          // Description in RU or fallback
          String desc = '';
          final langRu = current['lang_ru'] as List?;
          if (langRu != null && langRu.isNotEmpty) {
            desc = langRu.first['value'] ?? '';
          }
          if (desc.isEmpty) {
            final weatherDesc = current['weatherDesc'] as List?;
            if (weatherDesc != null && weatherDesc.isNotEmpty) {
              desc = weatherDesc.first['value'] ?? '';
            }
          }

          final buffer = StringBuffer();
          buffer.writeln('=== ДАННЫЕ О ПОГОДЕ (wttr.in) ===');
          buffer.writeln('Город/Локация: $city');
          buffer.writeln('Текущая температура: $tempC°C (ощущается как $feelsLikeC°C)');
          if (desc.isNotEmpty) {
            buffer.writeln('Погодные условия: $desc');
          }
          buffer.writeln('Влажность: $humidity%');
          buffer.writeln('Ветер: $windKmh км/ч');

          // Add today's forecast if present
          final weatherList = data['weather'] as List?;
          if (weatherList != null && weatherList.isNotEmpty) {
            final today = weatherList.first as Map<String, dynamic>;
            final maxT = today['maxtempC'] ?? '?';
            final minT = today['mintempC'] ?? '?';
            buffer.writeln('Прогноз на сегодня: макс $maxT°C, мин $minT°C');

            if (weatherList.length > 1) {
              final tomorrow = weatherList[1] as Map<String, dynamic>;
              final maxTom = tomorrow['maxtempC'] ?? '?';
              final minTom = tomorrow['mintempC'] ?? '?';
              buffer.writeln('Прогноз на завтра: макс $maxTom°C, мин $minTom°C');
            }
          }

          buffer.writeln('=== КОНЕЦ ДАННЫХ О ПОГОДЕ ===');
          return buffer.toString();
        }
      }
    } catch (e) {
      debugPrint('[WEATHER] Ошибка wttr.in JSON: $e. Пробуем строковый формат...');
    }

    // Fallback: simple format string
    try {
      final encoded = Uri.encodeComponent(city);
      final simpleUrl = 'https://wttr.in/$encoded?format=3&lang=ru';
      final response = await _dio.get<String>(simpleUrl);
      if (response.data != null && response.data!.trim().isNotEmpty) {
        return '=== ДАННЫЕ О ПОГОДЕ ===\n${response.data!.trim()}\n=== КОНЕЦ ДАННЫХ ===';
      }
    } catch (e) {
      debugPrint('[WEATHER] Ошибка строкового формата wttr.in: $e');
    }

    return null;
  }

  String _decodeHtml(String raw) {
    return raw
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cleanDdgUrl(String rawUrl) {
    if (rawUrl.contains('uddg=')) {
      final match = RegExp(r'uddg=([^&]+)').firstMatch(rawUrl);
      if (match != null) {
        return Uri.decodeComponent(match.group(1)!);
      }
    }
    if (rawUrl.startsWith('//')) {
      return 'https:$rawUrl';
    }
    return rawUrl;
  }

  /// Real web search via DuckDuckGo HTML Search
  Future<List<SearchResult>> searchDuckDuckGoHtml(String query) async {
    final results = <SearchResult>[];
    try {
      final response = await _dio.post<String>(
        'https://html.duckduckgo.com/html/',
        data: {'q': query},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final html = response.data ?? '';
      if (html.isEmpty) return results;

      // Extract result snippets and titles
      final blockRegex = RegExp(
        r'<div class="result results_links[^"]*"[^>]*>([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>',
      );

      final matches = blockRegex.allMatches(html);
      for (final match in matches.take(5)) {
        final block = match.group(1) ?? '';

        // Title and URL
        final titleMatch = RegExp(
          r'<a class="result__a"[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>',
        ).firstMatch(block);

        final snippetMatch = RegExp(
          r'<a class="result__snippet"[^>]*>([\s\S]*?)<\/a>',
        ).firstMatch(block);

        if (snippetMatch != null) {
          final snippet = _decodeHtml(snippetMatch.group(1) ?? '');
          final title = titleMatch != null
              ? _decodeHtml(titleMatch.group(2) ?? '')
              : 'Результат поиска';
          final url = titleMatch != null
              ? _cleanDdgUrl(titleMatch.group(1) ?? '')
              : null;

          if (snippet.isNotEmpty) {
            results.add(
              SearchResult(title: title, snippet: snippet, url: url),
            );
          }
        }
      }

      // If block matching didn't yield items, fallback to direct snippet matching
      if (results.isEmpty) {
        final snippetMatches = RegExp(
          r'<a class="result__snippet"[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>',
        ).allMatches(html);

        for (final sm in snippetMatches.take(4)) {
          final snippet = _decodeHtml(sm.group(2) ?? '');
          final rawUrl = sm.group(1) ?? '';
          if (snippet.isNotEmpty) {
            results.add(
              SearchResult(
                title: 'Результат веб-поиска',
                snippet: snippet,
                url: _cleanDdgUrl(rawUrl),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[WEB SEARCH] DuckDuckGo HTML search error: $e');
    }
    return results;
  }

  /// DuckDuckGo Lite Search fallback
  Future<List<SearchResult>> searchDuckDuckGoLite(String query) async {
    final results = <SearchResult>[];
    try {
      final response = await _dio.post<String>(
        'https://lite.duckduckgo.com/lite/',
        data: {'q': query},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final html = response.data ?? '';
      if (html.isEmpty) return results;

      final snippetMatches = RegExp(
        r"<td class='result-snippet'>([\s\S]*?)<\/td>",
      ).allMatches(html);

      final linkMatches = RegExp(
        r"<a class='result-link'[^>]*href='([^']*)'[^>]*>([\s\S]*?)<\/a>",
      ).allMatches(html).toList();

      int idx = 0;
      for (final sm in snippetMatches.take(4)) {
        final snippet = _decodeHtml(sm.group(1) ?? '');
        String title = 'Результат поиска';
        String? url;

        if (idx < linkMatches.length) {
          title = _decodeHtml(linkMatches[idx].group(2) ?? title);
          url = _cleanDdgUrl(linkMatches[idx].group(1) ?? '');
        }

        if (snippet.isNotEmpty) {
          results.add(
            SearchResult(title: title, snippet: snippet, url: url),
          );
        }
        idx++;
      }
    } catch (e) {
      debugPrint('[WEB SEARCH] DuckDuckGo Lite search error: $e');
    }
    return results;
  }

  /// Performs full web search across the live internet
  Future<List<SearchResult>> search(String query) async {
    debugPrint('[WEB SEARCH] Выполняем реальный поиск в интернете: "$query"');

    // 1. Primary: DuckDuckGo HTML
    var results = await searchDuckDuckGoHtml(query);
    if (results.isNotEmpty) {
      debugPrint('[WEB SEARCH] Найдено через DuckDuckGo HTML: ${results.length}');
      return results;
    }

    // 2. Secondary: DuckDuckGo Lite
    debugPrint('[WEB SEARCH] Пробуем DuckDuckGo Lite...');
    results = await searchDuckDuckGoLite(query);
    if (results.isNotEmpty) {
      debugPrint('[WEB SEARCH] Найдено через DuckDuckGo Lite: ${results.length}');
      return results;
    }

    return [];
  }

  /// Builds context string for model from search results, weather, or URLs
  Future<String?> getWebContext(String userPrompt) async {
    final buffer = StringBuffer();

    // 1. If user provided a URL, read it directly
    if (containsUrl(userPrompt)) {
      final urls = extractUrls(userPrompt);
      final firstUrl = urls.first;
      final pageText = await fetchWebPageText(firstUrl);
      if (pageText != null && pageText.isNotEmpty) {
        return '=== СОДЕРЖИМОЕ СТРАНИЦЫ ($firstUrl) ===\n$pageText\n=== КОНЕЦ СОДЕРЖИМОГО ===';
      }
    }

    // 2. If prompt is weather-related, fetch real-time weather first!
    if (isWeatherQuery(userPrompt)) {
      final city = extractCity(userPrompt);
      final weatherData = await fetchWeather(city);
      if (weatherData != null && weatherData.isNotEmpty) {
        buffer.writeln(weatherData);
      }
    }

    // 3. Also run real web search
    final results = await search(userPrompt);
    if (results.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('=== РЕЗУЛЬТАТЫ ПОИСКА В ИНТЕРНЕТЕ ===');
      for (int i = 0; i < results.length; i++) {
        final r = results[i];
        buffer.writeln('${i + 1}. [${r.title}]');
        buffer.writeln('   ${r.snippet}');
        if (r.url != null && r.url!.isNotEmpty) {
          buffer.writeln('   Ссылка: ${r.url}');
        }
        buffer.writeln();
      }
      buffer.writeln('=== КОНЕЦ РЕЗУЛЬТАТОВ ПОИСКА ===');
    }

    final contextResult = buffer.toString().trim();
    if (contextResult.isEmpty) return null;

    return contextResult;
  }
}
