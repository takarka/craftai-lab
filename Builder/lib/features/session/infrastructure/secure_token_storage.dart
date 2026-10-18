import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/auth_tokens.dart';

abstract interface class SecureTokenStorage {
  Future<void> writeSession({
    required String ownerId,
    required AuthTokens tokens,
  });
  Future<AuthTokens?> readTokens();

  /// Forces one mobile-token rotation. Implementations must coalesce callers.
  Future<AuthTokens?> refreshTokens();
  Future<StoredRefreshSession?> readRefreshSession();
  Future<String?> readOwnerId();
  Future<void> clearSession();
  Future<bool> hasStoredSession();
}

class StoredRefreshSession {
  const StoredRefreshSession({
    required this.ownerId,
    required this.refreshToken,
    required this.refreshExpiresAtUtc,
  });
  final String ownerId;
  final String refreshToken;
  final DateTime refreshExpiresAtUtc;
}

final class PlatformSecureTokenStorage implements SecureTokenStorage {
  PlatformSecureTokenStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;
  AuthTokens? _memoryTokens;

  static const _keyRefreshToken = 'craftai_refresh_token';
  static const _keyTokenType = 'craftai_token_type';
  static const _keyTokenExpires = 'craftai_token_expires_at';
  static const _keyRefreshExpires = 'craftai_refresh_expires_at';
  static const _keyOwnerId = 'craftai_session_owner_id';

  @override
  Future<void> writeSession({
    required String ownerId,
    required AuthTokens tokens,
  }) async {
    await _storage.write(key: _keyOwnerId, value: ownerId);
    // Access tokens deliberately never enter OS storage. They live only for
    // this process lifetime; a cold start uses the persisted refresh token.
    _memoryTokens = tokens;
    await _storage.write(key: _keyRefreshToken, value: tokens.refreshToken);
    await _storage.write(key: _keyTokenType, value: tokens.tokenType);
    await _storage.write(
      key: _keyTokenExpires,
      value: tokens.expiresAtUtc.toIso8601String(),
    );
    await _storage.write(
      key: _keyRefreshExpires,
      value: tokens.refreshExpiresAtUtc.toIso8601String(),
    );
  }

  @override
  Future<AuthTokens?> readTokens() async {
    return _memoryTokens;
  }

  @override
  Future<AuthTokens?> refreshTokens() async => null;

  @override
  Future<StoredRefreshSession?> readRefreshSession() async {
    final ownerId = await _storage.read(key: _keyOwnerId);
    final refreshToken = await _storage.read(key: _keyRefreshToken);
    final expiry = await _storage.read(key: _keyRefreshExpires);
    if (ownerId == null || refreshToken == null || expiry == null) return null;
    final parsed = DateTime.tryParse(expiry);
    if (ownerId.isEmpty || refreshToken.isEmpty || parsed == null) return null;
    return StoredRefreshSession(
      ownerId: ownerId,
      refreshToken: refreshToken,
      refreshExpiresAtUtc: parsed.toUtc(),
    );
  }

  @override
  Future<String?> readOwnerId() async {
    return await _storage.read(key: _keyOwnerId);
  }

  @override
  Future<void> clearSession() async {
    await _storage.delete(key: _keyOwnerId);
    _memoryTokens = null;
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyTokenType);
    await _storage.delete(key: _keyTokenExpires);
    await _storage.delete(key: _keyRefreshExpires);
  }

  @override
  Future<bool> hasStoredSession() async {
    final ownerId = await readOwnerId();
    return ownerId != null && ownerId.trim().isNotEmpty;
  }
}

final class InMemorySecureTokenStorage implements SecureTokenStorage {
  final Map<String, String> _storage = {};

  @override
  Future<void> writeSession({
    required String ownerId,
    required AuthTokens tokens,
  }) async {
    _storage['owner_id'] = ownerId;
    _tokens = tokens;
    _storage['refresh_token'] = tokens.refreshToken;
    _storage['token_type'] = tokens.tokenType;
    _storage['expires_at'] = tokens.expiresAtUtc.toIso8601String();
    _storage['refresh_expires_at'] = tokens.refreshExpiresAtUtc
        .toIso8601String();
  }

  AuthTokens? _tokens;

  @override
  Future<AuthTokens?> readTokens() async {
    return _tokens;
  }

  @override
  Future<AuthTokens?> refreshTokens() async => null;

  @override
  Future<StoredRefreshSession?> readRefreshSession() async {
    final ownerId = _storage['owner_id'];
    final refreshToken = _storage['refresh_token'];
    final expiry = _storage['refresh_expires_at'];
    final parsed = expiry == null ? null : DateTime.tryParse(expiry);
    if (ownerId == null || refreshToken == null || parsed == null) return null;
    return StoredRefreshSession(
      ownerId: ownerId,
      refreshToken: refreshToken,
      refreshExpiresAtUtc: parsed.toUtc(),
    );
  }

  @override
  Future<String?> readOwnerId() async => _storage['owner_id'];

  @override
  Future<void> clearSession() async {
    _tokens = null;
    _storage.clear();
  }

  @override
  Future<bool> hasStoredSession() async => _storage.containsKey('owner_id');
}
