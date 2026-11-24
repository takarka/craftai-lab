import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/transfer_review.dart';

/// The seventh lesson's synthetic exercise stays on this device/browser.
final class TransferReviewStore {
  const TransferReviewStore([
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    ),
  ]);

  final FlutterSecureStorage storage;

  String _key(String ownerId) =>
      'craftai_transfer_review_v1_${Uri.encodeComponent(ownerId)}';

  Future<TransferReview?> read(String ownerId) async {
    final value = await storage.read(key: _key(ownerId));
    if (value == null) return null;
    return TransferReview.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  Future<void> write(String ownerId, TransferReview review) =>
      storage.write(key: _key(ownerId), value: jsonEncode(review.toJson()));

  Future<void> clear(String ownerId) => storage.delete(key: _key(ownerId));
}
