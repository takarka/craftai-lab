import 'dart:convert';
import 'package:builder/core/errors/app_failure.dart';
import 'package:builder/features/auth/infrastructure/craft_ai_auth_gateway.dart';
import 'package:builder/features/session/domain/auth_tokens.dart';
import 'package:builder/features/session/infrastructure/secure_token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class InMemoryTokenStorage implements SecureTokenStorage {
  String? _ownerId;
  AuthTokens? _tokens;

  @override
  Future<bool> hasStoredSession() async => _tokens != null;

  @override
  Future<String?> readOwnerId() async => _ownerId;

  @override
  Future<AuthTokens?> readTokens() async => _tokens;

  @override
  Future<AuthTokens?> refreshTokens() async => null;

  @override
  Future<StoredRefreshSession?> readRefreshSession() async => null;

  @override
  Future<void> writeSession({
    required String ownerId,
    required AuthTokens tokens,
  }) async {
    _ownerId = ownerId;
    _tokens = tokens;
  }

  @override
  Future<void> clearSession() async {
    _ownerId = null;
    _tokens = null;
  }
}

void main() {
  group('CraftAiAuthGateway', () {
    final baseUri = Uri.parse('https://localhost:5001');

    test('isAvailable is true and provides default legal documents', () {
      final gateway = CraftAiAuthGateway(
        baseUri: baseUri,
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      );

      expect(gateway.isAvailable, isTrue);
      final ruDocs = gateway.documentsFor('ru');
      expect(ruDocs, isNotNull);
      expect(ruDocs!.isUsable, isTrue);
      expect(ruDocs.terms.revision, '2026.1-ru');

      final kkDocs = gateway.documentsFor('kk');
      expect(kkDocs, isNotNull);
      expect(kkDocs!.isUsable, isTrue);
      expect(kkDocs.terms.revision, '2026.1-kk');
    });

    test('signIn succeeds and writes session tokens', () async {
      final tokenStorage = InMemoryTokenStorage();
      final mockClient = MockClient((request) async {
        if (request.url.path == '/mobile/auth/login') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['email'], 'teacher1@craftai.kz');
          expect(body['password'], 'TeacherPass123!');
          return http.Response(
            jsonEncode({
              'accessToken': 'jwt_access_123',
              'refreshToken': 'refresh_xyz',
              'accessTokenExpiresAtUtc': DateTime.now()
                  .add(const Duration(minutes: 15))
                  .toUtc()
                  .toIso8601String(),
              'refreshExpiresAtUtc': DateTime.now()
                  .add(const Duration(days: 30))
                  .toUtc()
                  .toIso8601String(),
              'userId': '00000000-0000-0000-0000-0000000000d1',
              'email': 'teacher1@craftai.kz',
              'fullName': 'Марат Ахметов',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final gateway = CraftAiAuthGateway(
        baseUri: baseUri,
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      await gateway.signIn(
        email: 'teacher1@craftai.kz',
        password: 'TeacherPass123!',
      );

      final ownerId = await tokenStorage.readOwnerId();
      final tokens = await tokenStorage.readTokens();
      expect(ownerId, '00000000-0000-0000-0000-0000000000d1');
      expect(tokens?.accessToken, 'jwt_access_123');
      expect(tokens?.refreshToken, 'refresh_xyz');
    });

    test('signIn throws invalidCredentials on 401', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 'login.invalid-credentials',
            'message': 'Неверный e-mail или пароль.',
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final gateway = CraftAiAuthGateway(
        baseUri: baseUri,
        httpClient: mockClient,
      );

      expect(
        () => gateway.signIn(email: 'wrong@mail.kz', password: 'bad'),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.code,
            'code',
            AppFailureCode.invalidCredentials,
          ),
        ),
      );
    });

    test('signIn throws rateLimited on 429', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Too many requests', 429);
      });

      final gateway = CraftAiAuthGateway(
        baseUri: baseUri,
        httpClient: mockClient,
      );

      expect(
        () => gateway.signIn(email: 'user@mail.kz', password: 'pwd'),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.code,
            'code',
            AppFailureCode.rateLimited,
          ),
        ),
      );
    });

    test('register succeeds and writes session tokens', () async {
      final tokenStorage = InMemoryTokenStorage();
      final mockClient = MockClient((request) async {
        if (request.url.path == '/mobile/auth/register') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['name'], 'New User');
          expect(body['email'], 'new@mail.kz');
          return http.Response(
            jsonEncode({
              'accessToken': 'jwt_reg_token',
              'refreshToken': 'refresh_reg_token',
              'accessTokenExpiresAtUtc': DateTime.now()
                  .add(const Duration(minutes: 15))
                  .toUtc()
                  .toIso8601String(),
              'refreshExpiresAtUtc': DateTime.now()
                  .add(const Duration(days: 30))
                  .toUtc()
                  .toIso8601String(),
              'userId': '11111111-1111-1111-1111-111111111111',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final gateway = CraftAiAuthGateway(
        baseUri: baseUri,
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      await gateway.register(
        name: 'New User',
        email: 'new@mail.kz',
        password: 'Password123!',
        termsRevision: '2026.1-ru',
        privacyRevision: '2026.1-ru',
      );

      expect(
        await tokenStorage.readOwnerId(),
        '11111111-1111-1111-1111-111111111111',
      );
      expect((await tokenStorage.readTokens())?.accessToken, 'jwt_reg_token');
    });

    test(
      'register maps AUTH_WEAK_PASSWORD to weakPassword AppFailure',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'code': 'AUTH_WEAK_PASSWORD',
              'message': 'Password does not meet policy.',
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        });

        final gateway = CraftAiAuthGateway(
          baseUri: baseUri,
          httpClient: mockClient,
        );

        expect(
          () => gateway.register(
            name: 'User',
            email: 'u@m.kz',
            password: '123',
            termsRevision: '1',
            privacyRevision: '1',
          ),
          throwsA(
            isA<AppFailure>().having(
              (f) => f.code,
              'code',
              AppFailureCode.weakPassword,
            ),
          ),
        );
      },
    );

    test(
      'password recovery and reset requests call backend endpoints',
      () async {
        var forgotCalled = false;
        var resetCalled = false;

        final mockClient = MockClient((request) async {
          if (request.url.path == '/mobile/auth/forgot-password') {
            forgotCalled = true;
            return http.Response('', 200);
          }
          if (request.url.path == '/mobile/auth/reset-password') {
            resetCalled = true;
            return http.Response('', 204);
          }
          return http.Response('Not Found', 404);
        });

        final gateway = CraftAiAuthGateway(
          baseUri: baseUri,
          httpClient: mockClient,
        );

        await gateway.requestPasswordReset(email: 'user@mail.kz');
        expect(forgotCalled, isTrue);

        await gateway.resetPassword(
          token: 'reset-token',
          newPassword: 'NewPassword123!',
        );
        expect(resetCalled, isTrue);
      },
    );
  });
}
