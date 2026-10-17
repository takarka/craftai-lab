import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureKeyStorage {
  Future<List<int>> getOrCreateStorageKey({required String installationId});
  Future<void> clearStorageKey({required String installationId});
}

class SecureKeyUnavailableException implements Exception {
  const SecureKeyUnavailableException(this.message);
  final String message;

  @override
  String toString() => 'SecureKeyUnavailableException: $message';
}

/// Production secure key storage backed by OS Keychain / Android Keystore.
final class PlatformSecureKeyStorage implements SecureKeyStorage {
  const PlatformSecureKeyStorage({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(resetOnError: true),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        );

  final FlutterSecureStorage _storage;
  static const _keyPrefix = 'craftai_builder_storage_key_';

  @override
  Future<List<int>> getOrCreateStorageKey({required String installationId}) async {
    if (installationId.trim().isEmpty) {
      throw const SecureKeyUnavailableException('Installation ID is required.');
    }
    final keyName = '$_keyPrefix$installationId';
    try {
      final existing = await _storage.read(key: keyName);
      if (existing != null && existing.isNotEmpty) {
        return base64Decode(existing);
      }
      final secureRandom = Random.secure();
      final newKey = List<int>.generate(32, (_) => secureRandom.nextInt(256));
      await _storage.write(key: keyName, value: base64Encode(newKey));
      return newKey;
    } catch (e) {
      throw SecureKeyUnavailableException('Failed to access hardware keystore: $e');
    }
  }

  @override
  Future<void> clearStorageKey({required String installationId}) async {
    final keyName = '$_keyPrefix$installationId';
    try {
      await _storage.delete(key: keyName);
    } catch (e) {
      throw SecureKeyUnavailableException('Failed to remove keystore entry: $e');
    }
  }
}

/// In-memory secure key storage for tests and isolated preview mode.
final class InMemorySecureKeyStorage implements SecureKeyStorage {
  InMemorySecureKeyStorage();

  final Map<String, List<int>> _keys = {};

  @override
  Future<List<int>> getOrCreateStorageKey({required String installationId}) async {
    if (installationId.trim().isEmpty) {
      throw const SecureKeyUnavailableException('Installation ID is required.');
    }
    return _keys.putIfAbsent(installationId, () {
      final random = Random.secure();
      return List<int>.generate(32, (_) => random.nextInt(256));
    });
  }

  @override
  Future<void> clearStorageKey({required String installationId}) async {
    _keys.remove(installationId);
  }
}
