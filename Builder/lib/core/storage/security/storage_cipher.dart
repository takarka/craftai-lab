import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class CipherDecryptionException implements Exception {
  const CipherDecryptionException([
    this.message = 'Integrity check failed or invalid key.',
  ]);
  final String message;

  @override
  String toString() => 'CipherDecryptionException: $message';
}

/// Authenticated payload encryptor for sensitive persisted fields and database payloads.
/// Employs HMAC-SHA256 authenticated keystream construction with 16-byte random IV
/// and 32-byte HMAC integrity verification to detect any tampering or wrong keys.
final class StorageCipher {
  const StorageCipher({required this.key});

  /// 256-bit symmetric key.
  final List<int> key;

  static const int ivLength = 16;
  static const int tagLength = 32;

  /// Encrypts plain UTF-8 text into an authenticated Base64 payload:
  /// `[16-byte IV][32-byte HMAC Tag][Ciphertext]`
  String encrypt(String plainText) {
    if (key.length < 32) {
      throw ArgumentError('Storage encryption key must be at least 32 bytes.');
    }
    final plainBytes = utf8.encode(plainText);
    final secureRandom = Random.secure();
    final iv = List<int>.generate(ivLength, (_) => secureRandom.nextInt(256));

    // Derive keystream using HMAC-SHA256 counter mode over IV + Key
    final cipherBytes = _applyKeystream(plainBytes, key, iv);

    // Compute HMAC-SHA256 tag over IV + Ciphertext
    final hmac = Hmac(sha256, key);
    final tag = hmac.convert([...iv, ...cipherBytes]).bytes;

    final result = Uint8List(ivLength + tagLength + cipherBytes.length);
    result.setRange(0, ivLength, iv);
    result.setRange(ivLength, ivLength + tagLength, tag);
    result.setRange(ivLength + tagLength, result.length, cipherBytes);

    return base64Encode(result);
  }

  /// Decrypts authenticated Base64 payload, throwing [CipherDecryptionException]
  /// if the data was modified, truncated, or encrypted with a different key.
  String decrypt(String cipherTextBase64) {
    if (key.length < 32) {
      throw ArgumentError('Storage encryption key must be at least 32 bytes.');
    }
    final rawBytes = base64Decode(cipherTextBase64);
    if (rawBytes.length < ivLength + tagLength) {
      throw const CipherDecryptionException(
        'Payload is too short to be valid.',
      );
    }

    final iv = rawBytes.sublist(0, ivLength);
    final expectedTag = rawBytes.sublist(ivLength, ivLength + tagLength);
    final cipherBytes = rawBytes.sublist(ivLength + tagLength);

    final hmac = Hmac(sha256, key);
    final calculatedTag = hmac.convert([...iv, ...cipherBytes]).bytes;

    if (!_constantTimeEquals(expectedTag, calculatedTag)) {
      throw const CipherDecryptionException();
    }

    final plainBytes = _applyKeystream(cipherBytes, key, iv);
    try {
      return utf8.decode(plainBytes);
    } catch (_) {
      throw const CipherDecryptionException(
        'Failed to decode UTF-8 plaintext.',
      );
    }
  }

  static List<int> _applyKeystream(
    List<int> input,
    List<int> key,
    List<int> iv,
  ) {
    final output = Uint8List(input.length);
    final hmac = Hmac(sha256, key);
    var blockIndex = 0;
    var offset = 0;

    while (offset < input.length) {
      final counterBytes = [
        (blockIndex >> 24) & 0xFF,
        (blockIndex >> 16) & 0xFF,
        (blockIndex >> 8) & 0xFF,
        blockIndex & 0xFF,
      ];
      final keyBlock = hmac.convert([...iv, ...counterBytes]).bytes;
      final bytesToXor = min(keyBlock.length, input.length - offset);
      for (var i = 0; i < bytesToXor; i++) {
        output[offset + i] = input[offset + i] ^ keyBlock[i];
      }
      offset += bytesToXor;
      blockIndex++;
    }
    return output;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
