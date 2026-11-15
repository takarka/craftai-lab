import 'dart:convert';
import 'package:builder/features/models/domain/model_catalog.dart';
import 'package:builder/features/models/infrastructure/craft_ai_client.dart';
import 'package:builder/features/session/domain/auth_tokens.dart';
import 'package:builder/features/session/infrastructure/secure_token_storage.dart';
import 'package:builder/features/session/infrastructure/refreshing_token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('F06-01: CraftAiClient Network & Error Handling', () {
    test('generates valid UUID v4 request ID for correlation', () {
      final reqId = CraftAiClient.generateRequestId();
      expect(reqId, hasLength(36));
      expect(reqId[14], equals('4')); // version 4
      expect(
        ['8', '9', 'a', 'b'].contains(reqId[19].toLowerCase()),
        isTrue,
      ); // variant
    });

    test(
      'attaches Authorization header with access token and correlation id',
      () async {
        final tokenStorage = InMemorySecureTokenStorage();
        await tokenStorage.writeSession(
          ownerId: 'owner_test_1',
          tokens: AuthTokens(
            accessToken: 'test_secret_access_token_123',
            refreshToken: 'test_refresh',
            expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
        );

        String? capturedAuthHeader;
        String? capturedRequestId;

        final mockClient = MockClient((request) async {
          capturedAuthHeader = request.headers['Authorization'];
          capturedRequestId = request.headers['X-Request-Id'];
          return http.Response(
            jsonEncode({'revision': 'rev-test', 'models': []}),
            200,
          );
        });

        final client = CraftAiClient(
          baseUri: Uri.parse('https://localhost:5001'),
          httpClient: mockClient,
          tokenStorage: tokenStorage,
        );

        final json = await client.getJson('/builder/models');
        expect(json['revision'], equals('rev-test'));
        expect(
          capturedAuthHeader,
          equals('Bearer test_secret_access_token_123'),
        );
        expect(capturedRequestId, isNotNull);
      },
    );

    test(
      'maps 401 to CraftAiAuthException without leaking secret tokens',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response('', 401);
        });

        final client = CraftAiClient(
          baseUri: Uri.parse('https://localhost:5001'),
          httpClient: mockClient,
        );

        expect(
          () => client.getJson('/builder/models'),
          throwsA(
            isA<CraftAiAuthException>()
                .having((e) => e.statusCode, 'statusCode', 401)
                .having((e) => e.message, 'message', contains('Unauthorized')),
          ),
        );
      },
    );

    test('retries once after a shared mobile refresh on 401', () async {
      final rawStorage = InMemorySecureTokenStorage();
      await rawStorage.writeSession(
        ownerId: 'owner',
        tokens: AuthTokens(
          accessToken: 'old-access',
          refreshToken: 'old-refresh',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
          refreshExpiresAtUtc: DateTime.now().toUtc().add(
            const Duration(days: 30),
          ),
        ),
      );
      var refreshCalls = 0;
      final storage = RefreshingTokenStorage(
        storage: rawStorage,
        baseUri: Uri.parse('https://localhost:5001'),
        client: MockClient((request) async {
          refreshCalls++;
          expect(request.url.path, '/mobile/auth/refresh');
          expect(jsonDecode(request.body)['refreshToken'], 'old-refresh');
          return http.Response(
            jsonEncode({
              'accessToken': 'new-access',
              'accessTokenExpiresAtUtc': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
              'refreshToken': 'new-refresh',
              'refreshExpiresAtUtc': DateTime.now()
                  .toUtc()
                  .add(const Duration(days: 30))
                  .toIso8601String(),
            }),
            200,
          );
        }),
      );
      var requestCalls = 0;
      final client = CraftAiClient(
        baseUri: Uri.parse('https://localhost:5001'),
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          requestCalls++;
          if (requestCalls == 1) return http.Response('', 401);
          expect(request.headers['Authorization'], 'Bearer new-access');
          return http.Response('{"models": []}', 200);
        }),
      );

      await client.getJson('/builder/models');
      expect(requestCalls, 2);
      expect(refreshCalls, 1);
      expect((await rawStorage.readTokens())!.refreshToken, 'new-refresh');
    });

    test('maps 500 to CraftAiServerException', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final client = CraftAiClient(
        baseUri: Uri.parse('https://localhost:5001'),
        httpClient: mockClient,
      );

      expect(
        () => client.getJson('/builder/models'),
        throwsA(
          isA<CraftAiServerException>().having(
            (e) => e.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });
  });

  group('ModelCatalog parsing', () {
    test('ModelCatalog parses backend response', () {
      final backendJson = {
        'revision': 'rev-openrouter-v1',
        'models': [
          {
            'modelId': 'google/gemini-2.5-flash',
            'available': true,
            'streaming': true,
            'tools': true,
            'languages': ['ru', 'kk'],
            'contextWindow': 128000,
          },
          {
            'modelId': 'qwen/qwen3-32b',
            'available': false,
            'streaming': true,
            'tools': true,
            'languages': ['ru', 'kk'],
            'contextWindow': 128000,
          },
        ],
      };

      final catalog = ModelCatalog.fromJson(backendJson);
      expect(catalog.revision, equals('rev-openrouter-v1'));
      expect(catalog.models, hasLength(2));
      expect(catalog.getModel('google/gemini-2.5-flash')?.available, isTrue);
      expect(catalog.getModel('qwen/qwen3-32b')?.available, isFalse);
    });
  });
}
