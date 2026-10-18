import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/auth_tokens.dart';
import 'secure_token_storage.dart';

/// Renews expired access tokens once for all concurrent API requests.
final class RefreshingTokenStorage implements SecureTokenStorage {
  RefreshingTokenStorage({
    required this.storage,
    required this.baseUri,
    required this.client,
  });

  final SecureTokenStorage storage;
  final Uri baseUri;
  final http.Client client;
  Future<AuthTokens?>? _pending;
  int _generation = 0;

  @override
  Future<AuthTokens?> readTokens() async {
    final tokens = await storage.readTokens();
    if (tokens != null && !tokens.isExpired) return tokens;
    return refreshTokens();
  }

  @override
  Future<AuthTokens?> refreshTokens() async {
    final tokens = await storage.readTokens();
    final stored = tokens == null ? await storage.readRefreshSession() : null;
    if (tokens == null && stored == null) return null;
    if (stored != null &&
        DateTime.now().toUtc().isAfter(stored.refreshExpiresAtUtc)) {
      await clearSession();
      return null;
    }
    final pending = _pending;
    if (pending != null) return pending;
    final refresh = _refresh(
      tokens ??
          AuthTokens(
            accessToken: '',
            refreshToken: stored!.refreshToken,
            expiresAtUtc: DateTime.utc(1970),
            refreshExpiresAtUtc: stored.refreshExpiresAtUtc,
          ),
      _generation,
    );
    _pending = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_pending, refresh)) _pending = null;
    }
  }

  Future<AuthTokens?> _refresh(AuthTokens old, int generation) async {
    final ownerId = await storage.readOwnerId();
    if (ownerId == null) return null;
    try {
      final response = await client
          .post(
            baseUri.resolve('/mobile/auth/refresh'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'refreshToken': old.refreshToken}),
          )
          .timeout(const Duration(seconds: 15));
      if (generation != _generation) return null;
      if (response.statusCode != 200) {
        await clearSession();
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final access = data['accessToken'] as String?;
      final refresh = data['refreshToken'] as String?;
      final expiry = DateTime.tryParse(
        data['accessTokenExpiresAtUtc'] as String? ?? '',
      );
      final refreshExpiry = DateTime.tryParse(
        data['refreshExpiresAtUtc'] as String? ?? '',
      );
      if (access == null ||
          access.isEmpty ||
          refresh == null ||
          refresh.isEmpty ||
          expiry == null ||
          refreshExpiry == null) {
        await clearSession();
        return null;
      }
      final tokens = AuthTokens(
        accessToken: access,
        refreshToken: refresh,
        expiresAtUtc: expiry.toUtc(),
        refreshExpiresAtUtc: refreshExpiry.toUtc(),
      );
      await storage.writeSession(ownerId: ownerId, tokens: tokens);
      return tokens;
    } catch (_) {
      if (generation == _generation) await clearSession();
      return null;
    }
  }

  @override
  Future<void> writeSession({
    required String ownerId,
    required AuthTokens tokens,
  }) {
    _generation++;
    _pending = null;
    return storage.writeSession(ownerId: ownerId, tokens: tokens);
  }

  @override
  Future<void> clearSession() {
    _generation++;
    _pending = null;
    return storage.clearSession();
  }

  @override
  Future<String?> readOwnerId() => storage.readOwnerId();

  @override
  Future<bool> hasStoredSession() => storage.hasStoredSession();

  @override
  Future<StoredRefreshSession?> readRefreshSession() =>
      storage.readRefreshSession();
}
