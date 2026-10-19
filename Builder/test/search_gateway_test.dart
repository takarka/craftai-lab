import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:builder/features/tools/infrastructure/search_adapter.dart';

void main() {
  SearchAdapter adapter(http.Response Function(http.Request) handler) =>
      SearchAdapter(
        language: 'kk',
        client: CraftAiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((request) async => handler(request)),
        ),
      );

  test(
    'uses real POST contract and preserves source and empty results',
    () async {
      final search = adapter((request) {
        expect(request.method, 'POST');
        expect(request.url.path, '/builder/search');
        expect(jsonDecode(request.body), {
          'query': 'сабақ',
          'language': 'kk',
          'limit': 5,
        });
        expect(request.headers['X-Request-Id'], isNotEmpty);
        return http.Response(
          jsonEncode({
            'source': 'provider',
            'results': [
              {
                'title': 'Материал',
                'url': 'https://example.test/lesson',
                'snippet': 'Мәтін',
                'source': 'example.test',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final hits = await search.search(' сабақ ');
      expect(hits.single.source, 'example.test');
      expect(hits.single.toMap()['url'], 'https://example.test/lesson');
      expect(
        await adapter((_) => http.Response('{"results":[]}', 200)).search('x'),
        isEmpty,
      );
    },
  );

  test('errors never produce fictional sources', () async {
    for (final status in [401, 403, 429, 500]) {
      await expectLater(
        adapter((_) => http.Response('{}', status)).search('x'),
        throwsA(isA<CraftAiException>()),
      );
    }
    await expectLater(
      const SearchAdapter().search('x'),
      throwsA(isA<CraftAiNetworkException>()),
    );
    await expectLater(
      adapter((_) => http.Response('broken', 200)).search('x'),
      throwsA(isA<CraftAiException>()),
    );
  });

  test('rejects invalid queries and unsafe result links', () async {
    var requests = 0;
    final search = adapter((_) {
      requests++;
      return http.Response(
        '{"results":[{"title":"x","url":"javascript:alert(1)","snippet":"x"}]}',
        200,
      );
    });
    await expectLater(search.search(' '), throwsArgumentError);
    await expectLater(search.search('x' * 501), throwsArgumentError);
    expect(requests, 0);
    await expectLater(search.search('x'), throwsFormatException);
  });
}
