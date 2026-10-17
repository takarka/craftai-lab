import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/auth_tokens.dart';

abstract interface class SecureTokenStorage {
  Future<void> writeSession({required String ownerId, required AuthTokens tokens});
  Future<AuthTokens?> readTokens();
  Future<String?> readOwnerId();
  Future<void> clearSession();
  Future<bool> hasStoredSession();
}

final class PlatformSecureTokenStorage implements SecureTokenStorage {
  const PlatformSecureTokenStorage({
    FlutterSecureStorage? storage,
  }) : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  static const _keyAccessToken = 'craftai_access_token';
  static const _keyRefreshToken = 'craftai_refresh_token';
  static const _keyTokenType = 'craftai_token_type';
  static const _keyTokenExpires = 'craftai_token_expires_at';
  static const _keyOwnerId = 'craftai_session_owner_id';

  @override
  Future<void> writeSession({
    required String ownerId,
    required AuthTokens tokens,
  }) async {
    await _storage.write(key: _keyOwnerId, value: ownerId);
    await _storage.write(key: _keyAccessToken, value: tokens.accessToken);
    await _storage.write(key: _keyRefreshToken, value: tokens.refreshToken);
    await _storage.write(key: _keyTokenType, value: tokens.tokenType);
    await _storage.write(
      key: _keyTokenExpires,
      value: tokens.expiresAtUtc.toIso8601String(),
    );
  }

  @override
  Future<AuthTokens?> readTokens() async {
    final access = await _storage.read(key: _keyAccessToken);
    final refresh = await _storage.read(key: _keyRefreshToken);
    final expires = await _storage.read(key: _keyTokenExpires);
    final type = await _storage.read(key: _keyTokenType) ?? 'Bearer';

    if (access == null || refresh == null || expires == null) {
      return null;
    }

    try {
      return AuthTokens(
        accessToken: access,
        refreshToken: refresh,
        tokenType: type,
        expiresAtUtc: DateTime.parse(expires).toUtc(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> readOwnerId() async {
    return await _storage.read(key: _keyOwnerId);
  }

  @override
  Future<void> clearSession() async {
    await _storage.delete(key: _keyOwnerId);
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyTokenType);
    await _storage.delete(key: _keyTokenExpires);
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
    _storage['access_token'] = tokens.accessToken;
    _storage['refresh_token'] = tokens.refreshToken;
    _storage['token_type'] = tokens.tokenType;
    _storage['expires_at'] = tokens.expiresAtUtc.toIso8601String();
  }

  @override
  Future<AuthTokens?> readTokens() async {
    final access = _storage['access_token'];
    final refresh = _storage['refresh_token'];
    final expires = _storage['expires_at'];
    final type = _storage['token_type'] ?? 'Bearer';

    if (access == null || refresh == null || expires == null) return null;
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      tokenType: type,
      expiresAtUtc: DateTime.parse(expires).toUtc(),
    );
  }

  @override
  Future<String?> readOwnerId() async => _storage['owner_id'];

  @override
  Future<void> clearSession() async => _storage.clear();

  @override
  Future<bool> hasStoredSession() async => _storage.containsKey('owner_id');
}
