import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AuthCredentialsStorage {
  Future<({String email, String password})?> readLastCredentials();
  Future<void> saveLastCredentials({
    required String email,
    required String password,
  });
  Future<void> saveLastEmail(String email);
  Future<void> clearLastCredentials();
}

final class PlatformAuthCredentialsStorage implements AuthCredentialsStorage {
  PlatformAuthCredentialsStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;
  final Map<String, String> _memoryFallback = {};

  static const _keyEmail = 'craftai_last_auth_email';
  static const _keyPassword = 'craftai_last_auth_password';

  @override
  Future<({String email, String password})?> readLastCredentials() async {
    try {
      final email =
          await _storage.read(key: _keyEmail) ?? _memoryFallback[_keyEmail];
      final password =
          await _storage.read(key: _keyPassword) ??
          _memoryFallback[_keyPassword];
      if (email == null && password == null) return null;
      return (email: email ?? '', password: password ?? '');
    } catch (_) {
      final email = _memoryFallback[_keyEmail];
      final password = _memoryFallback[_keyPassword];
      if (email == null && password == null) return null;
      return (email: email ?? '', password: password ?? '');
    }
  }

  @override
  Future<void> saveLastCredentials({
    required String email,
    required String password,
  }) async {
    _memoryFallback[_keyEmail] = email;
    _memoryFallback[_keyPassword] = password;
    try {
      await _storage.write(key: _keyEmail, value: email);
      await _storage.write(key: _keyPassword, value: password);
    } catch (_) {}
  }

  @override
  Future<void> saveLastEmail(String email) async {
    _memoryFallback[_keyEmail] = email;
    try {
      await _storage.write(key: _keyEmail, value: email);
    } catch (_) {}
  }

  @override
  Future<void> clearLastCredentials() async {
    _memoryFallback.clear();
    try {
      await _storage.delete(key: _keyEmail);
      await _storage.delete(key: _keyPassword);
    } catch (_) {}
  }
}

final class InMemoryAuthCredentialsStorage implements AuthCredentialsStorage {
  String? _email;
  String? _password;

  @override
  Future<({String email, String password})?> readLastCredentials() async {
    if (_email == null && _password == null) return null;
    return (email: _email ?? '', password: _password ?? '');
  }

  @override
  Future<void> saveLastCredentials({
    required String email,
    required String password,
  }) async {
    _email = email;
    _password = password;
  }

  @override
  Future<void> saveLastEmail(String email) async {
    _email = email;
  }

  @override
  Future<void> clearLastCredentials() async {
    _email = null;
    _password = null;
  }
}
