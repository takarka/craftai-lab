import 'dart:async';
import 'dart:convert';

import 'package:builder/features/session/domain/auth_tokens.dart';
import 'package:builder/features/session/infrastructure/refreshing_token_storage.dart';
import 'package:builder/features/session/infrastructure/secure_token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late InMemorySecureTokenStorage storage;
  setUp(() async {
    storage = InMemorySecureTokenStorage();
    await storage.writeSession(
      ownerId: 'teacher',
      tokens: AuthTokens(
        accessToken: 'expired',
        refreshToken: 'refresh',
        expiresAtUtc: DateTime.utc(2020),
      ),
    );
  });

  test(
    'concurrent requests rotate an expired token once and persist the new session',
    () async {
      var calls = 0;
      final response = Completer<http.Response>();
      final refreshing = RefreshingTokenStorage(
        storage: storage,
        baseUri: Uri.parse('https://api.example.test'),
        client: MockClient((request) {
          calls++;
          expect(request.url.path, '/mobile/auth/refresh');
          expect(jsonDecode(request.body)['refreshToken'], 'refresh');
          return response.future;
        }),
      );
      final reads = Future.wait([
        refreshing.readTokens(),
        refreshing.readTokens(),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      response.complete(
        http.Response(
          jsonEncode({
            'accessToken': 'renewed',
            'refreshToken': 'rotated',
            'accessTokenExpiresAtUtc': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
            'refreshExpiresAtUtc': DateTime.now()
                .toUtc()
                .add(const Duration(days: 30))
                .toIso8601String(),
          }),
          200,
        ),
      );
      expect((await reads).map((t) => t!.accessToken), everyElement('renewed'));
      expect((await storage.readTokens())!.refreshToken, 'rotated');
      expect((await refreshing.readTokens())!.accessToken, 'renewed');
      expect(calls, 1);
    },
  );

  test('revoked refresh token clears the session', () async {
    final refreshing = RefreshingTokenStorage(
      storage: storage,
      baseUri: Uri.parse('https://api.example.test'),
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    expect(await refreshing.readTokens(), isNull);
    expect(await storage.readOwnerId(), isNull);
  });

  test('failed refresh clears the saved session', () async {
    final refreshing = RefreshingTokenStorage(
      storage: storage,
      baseUri: Uri.parse('https://api.example.test'),
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    expect(await refreshing.readTokens(), isNull);
    expect(await storage.readOwnerId(), isNull);
  });

  test('sign out during refresh cannot restore the old account', () async {
    final response = Completer<http.Response>();
    final refreshing = RefreshingTokenStorage(
      storage: storage,
      baseUri: Uri.parse('https://api.example.test'),
      client: MockClient((_) => response.future),
    );
    final pending = refreshing.readTokens();
    await Future<void>.delayed(Duration.zero);
    await refreshing.clearSession();
    response.complete(
      http.Response(
        jsonEncode({
          'accessToken': 'renewed',
          'refreshToken': 'rotated',
          'accessTokenExpiresAtUtc': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'refreshExpiresAtUtc': DateTime.now()
              .toUtc()
              .add(const Duration(days: 30))
              .toIso8601String(),
        }),
        200,
      ),
    );
    expect(await pending, isNull);
    expect(await storage.readTokens(), isNull);
  });
}
