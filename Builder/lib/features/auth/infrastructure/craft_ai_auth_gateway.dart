import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../core/errors/app_failure.dart';
import '../../session/domain/auth_tokens.dart';
import '../../session/infrastructure/persistent_session_repository.dart';
import '../../session/infrastructure/secure_token_storage.dart';
import '../../session/session_repository.dart';
import '../domain/auth_gateway.dart';

/// Real HTTP implementation of [AuthGateway] that connects to the CraftAI backend
/// (e.g. https://localhost:5001 or deployed staging/prod API).
class CraftAiAuthGateway implements AuthGateway {
  CraftAiAuthGateway({
    required this.baseUri,
    http.Client? httpClient,
    this.sessionRepository,
    this.tokenStorage,
  }) : _httpClient = httpClient ?? _createClient(baseUri) {
    _initDefaultDocuments();
  }

  static http.Client _createClient(Uri baseUri) {
    final isLoopback =
        ['localhost', '127.0.0.1', '10.0.2.2'].contains(baseUri.host) ||
        baseUri.host.startsWith('192.168.');
    if (isLoopback) {
      final io = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      return IOClient(io);
    }
    return http.Client();
  }

  final Uri baseUri;
  final http.Client _httpClient;
  final SessionRepository? sessionRepository;
  final SecureTokenStorage? tokenStorage;

  final Map<String, AuthLegalDocuments> _cachedDocuments = {};

  void _initDefaultDocuments() {
    _cachedDocuments['ru'] = const AuthLegalDocuments(
      terms: LegalDocument(
        revision: '2026.1-ru',
        body: 'Пользовательское соглашение CraftAI Lab.',
      ),
      privacy: LegalDocument(
        revision: '2026.1-ru',
        body: 'Политика конфиденциальности персональных данных CraftAI Lab.',
      ),
    );

    _cachedDocuments['kk'] = const AuthLegalDocuments(
      terms: LegalDocument(
        revision: '2026.1-kk',
        body: 'CraftAI Lab пайдаланушы келісімі.',
      ),
      privacy: LegalDocument(
        revision: '2026.1-kk',
        body: 'CraftAI Lab дербес деректерді қорғау саясаты.',
      ),
    );

    // Warm-up document revisions in background without blocking UI
    unawaited(fetchDocuments('ru'));
    unawaited(fetchDocuments('kk'));
  }

  Future<void> fetchDocuments(String languageCode) async {
    try {
      final uri = baseUri.resolve('/mobile/auth/documents?lang=$languageCode');
      final response = await _httpClient
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final lang = data['language'] as String? ?? languageCode;
        final termsRev = data['termsRevision'] as String? ?? '';
        final privRev = data['privacyRevision'] as String? ?? '';
        final termsTxt = data['termsText'] as String? ?? '';
        final privTxt = data['privacyText'] as String? ?? '';

        if (termsRev.isNotEmpty &&
            privRev.isNotEmpty &&
            termsTxt.isNotEmpty &&
            privTxt.isNotEmpty) {
          _cachedDocuments[lang] = AuthLegalDocuments(
            terms: LegalDocument(revision: termsRev, body: termsTxt),
            privacy: LegalDocument(revision: privRev, body: privTxt),
          );
        }
      }
    } catch (_) {
      // Retain pre-initialized valid fallback documents on connection issues
    }
  }

  @override
  bool get isAvailable => true;

  @override
  AuthLegalDocuments? documentsFor(String languageCode) {
    return _cachedDocuments[languageCode] ?? _cachedDocuments['ru'];
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    final uri = baseUri.resolve('/mobile/auth/login');
    try {
      final response = await _httpClient
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'email': email.trim(), 'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _handleAuthTokenResponse(data);
        return;
      }

      if (response.statusCode == 401) {
        throw const AppFailure(AppFailureCode.invalidCredentials);
      }
      if (response.statusCode == 429) {
        throw const AppFailure(AppFailureCode.rateLimited);
      }
      if (response.statusCode >= 500) {
        throw const AppFailure(AppFailureCode.serviceUnavailable);
      }

      final errorBody = _tryParseJson(response.body);
      final code = errorBody?['code']?.toString() ?? '';
      if (code.contains('invalid-credentials') ||
          code.contains('invalid-request')) {
        throw const AppFailure(AppFailureCode.invalidCredentials);
      }
      throw const AppFailure(AppFailureCode.serviceUnavailable);
    } on SocketException {
      throw const AppFailure(AppFailureCode.networkUnavailable);
    } on HandshakeException {
      throw const AppFailure(AppFailureCode.networkUnavailable);
    } on TimeoutException {
      throw const AppFailure(AppFailureCode.networkUnavailable);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(AppFailureCode.unexpected);
    }
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String termsRevision,
    required String privacyRevision,
  }) async {
    final uri = baseUri.resolve('/mobile/auth/register');
    try {
      final response = await _httpClient
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'name': name.trim(),
              'email': email.trim(),
              'password': password,
              'termsRevision': termsRevision,
              'privacyRevision': privacyRevision,
              'language': 'ru',
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _handleAuthTokenResponse(data);
        return;
      }

      final errorBody = _tryParseJson(response.body);
      final code = errorBody?['code']?.toString() ?? '';

      if (code == 'AUTH_WEAK_PASSWORD' ||
          response.statusCode == 400 && code.contains('WEAK_PASSWORD')) {
        throw const AppFailure(AppFailureCode.weakPassword);
      }
      if (response.statusCode == 409 ||
          code.contains('account-exists') ||
          code.contains('Duplicate')) {
        throw const AppFailure(AppFailureCode.accountExists);
      }
      if (response.statusCode == 429) {
        throw const AppFailure(AppFailureCode.rateLimited);
      }
      if (response.statusCode >= 500) {
        throw const AppFailure(AppFailureCode.serviceUnavailable);
      }

      throw const AppFailure(AppFailureCode.serviceUnavailable);
    } on SocketException {
      throw const AppFailure(AppFailureCode.networkUnavailable);
    } on TimeoutException {
      throw const AppFailure(AppFailureCode.networkUnavailable);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(AppFailureCode.unexpected);
    }
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    final uri = baseUri.resolve('/mobile/auth/forgot-password');
    try {
      final response = await _httpClient
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'email': email.trim(), 'language': 'ru'}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 429) {
        throw const AppFailure(AppFailureCode.rateLimited);
      }
      if (response.statusCode >= 500) {
        throw const AppFailure(AppFailureCode.serviceUnavailable);
      }
    } on SocketException {
      throw const AppFailure(AppFailureCode.networkUnavailable);
    } on TimeoutException {
      throw const AppFailure(AppFailureCode.networkUnavailable);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(AppFailureCode.unexpected);
    }
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final uri = baseUri.resolve('/mobile/auth/reset-password');
    try {
      final response = await _httpClient
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'token': token.trim(),
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      }

      final errorBody = _tryParseJson(response.body);
      final code = errorBody?['code']?.toString() ?? '';

      if (code == 'AUTH_WEAK_PASSWORD' ||
          response.statusCode == 400 && code.contains('WEAK_PASSWORD')) {
        throw const AppFailure(AppFailureCode.weakPassword);
      }
      if (response.statusCode == 429) {
        throw const AppFailure(AppFailureCode.rateLimited);
      }
      if (response.statusCode >= 500) {
        throw const AppFailure(AppFailureCode.serviceUnavailable);
      }

      throw const AppFailure(AppFailureCode.unexpected);
    } on SocketException {
      throw const AppFailure(AppFailureCode.networkUnavailable);
    } on TimeoutException {
      throw const AppFailure(AppFailureCode.networkUnavailable);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(AppFailureCode.unexpected);
    }
  }

  @override
  Future<void> changePassword({required String newPassword}) async {
    await _postAuthenticated('/mobile/auth/change-password', {
      'newPassword': newPassword,
    });
    if (sessionRepository is PersistentSessionRepository) {
      (sessionRepository as PersistentSessionRepository).markPasswordChanged();
    }
  }

  @override
  Future<void> logout() async {
    final tokens = tokenStorage == null
        ? null
        : await tokenStorage!.readTokens();
    final stored = tokenStorage == null
        ? null
        : await tokenStorage!.readRefreshSession();
    try {
      await _postAuthenticated('/mobile/auth/logout', {
        if (stored != null)
          'refreshToken': stored.refreshToken
        else if (tokens != null)
          'refreshToken': tokens.refreshToken,
      });
    } finally {
      // Logout is terminal even when the server cannot be reached.
      await tokenStorage?.clearSession();
    }
  }

  Future<void> _postAuthenticated(
    String path,
    Map<String, dynamic> body,
  ) async {
    final tokens = tokenStorage == null
        ? null
        : await tokenStorage!.readTokens();
    if (tokens == null) {
      throw const AppFailure(AppFailureCode.invalidCredentials);
    }
    try {
      final response = await _httpClient
          .post(
            baseUri.resolve(path),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${tokens.accessToken}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const AppFailure(AppFailureCode.serviceUnavailable);
      }
    } on TimeoutException {
      throw const AppFailure(AppFailureCode.networkUnavailable);
    } on SocketException {
      throw const AppFailure(AppFailureCode.networkUnavailable);
    }
  }

  Future<void> _handleAuthTokenResponse(Map<String, dynamic> data) async {
    final accessToken = data['accessToken'] as String? ?? '';
    final refreshToken = data['refreshToken'] as String? ?? '';
    final userId = data['userId'] as String? ?? '';
    final expiresStr = data['accessTokenExpiresAtUtc'] as String?;
    final refreshExpiresStr = data['refreshExpiresAtUtc'] as String?;

    if (accessToken.isEmpty ||
        refreshToken.isEmpty ||
        userId.isEmpty ||
        refreshExpiresStr == null) {
      throw const AppFailure(AppFailureCode.unexpected);
    }

    final expiresAtUtc = expiresStr != null
        ? (DateTime.tryParse(expiresStr)?.toUtc() ??
              DateTime.now().toUtc().add(const Duration(minutes: 15)))
        : DateTime.now().toUtc().add(const Duration(minutes: 15));

    final tokens = AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAtUtc: expiresAtUtc,
      refreshExpiresAtUtc:
          DateTime.tryParse(refreshExpiresStr)?.toUtc() ?? expiresAtUtc,
    );

    if (sessionRepository is PersistentSessionRepository) {
      await (sessionRepository as PersistentSessionRepository).saveSession(
        ownerId: userId,
        tokens: tokens,
        mustChangePassword: data['mustChangePassword'] == true,
      );
    } else if (tokenStorage != null) {
      await tokenStorage!.writeSession(ownerId: userId, tokens: tokens);
    }
  }

  Map<String, dynamic>? _tryParseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }
}
