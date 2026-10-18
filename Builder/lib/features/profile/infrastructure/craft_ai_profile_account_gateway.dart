import 'dart:convert';

import '../../models/infrastructure/craft_ai_client.dart';
import '../domain/profile.dart';

/// Adapter for B06's confirmed account-usage endpoint.
/// The server is authoritative: the client never invents a quota or balance.
class CraftAiProfileAccountGateway implements ProfileAccountGateway {
  CraftAiProfileAccountGateway(this._client);

  final CraftAiClient _client;

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteAccount(String ownerId) async {
    // Account deletion requires a confirmed server contract before it can be
    // reported as successful to the caller.
    throw UnsupportedError('Account deletion API is not connected');
  }

  @override
  Future<AccountSnapshot> load(String ownerId) async {
    final claims = await _identityClaims(ownerId);
    final name = claims['name'];
    final email = claims['email'];
    final role = claims['role'];
    final json = await _client.getJson('/me/usage');
    final status = json['status'] as String?;
    final tokens = json['tokens'] as Map<String, dynamic>?;
    if (status != 'available' || tokens == null) {
      return AccountSnapshot(
        ownerId: ownerId,
        name: name,
        email: email,
        role: role,
        updatedAtUtc: DateTime.now().toUtc(),
      );
    }

    int? readInt(Object? value) => switch (value) {
      int value => value,
      num value => value.toInt(),
      _ => null,
    };

    return AccountSnapshot(
      ownerId: ownerId,
      name: name,
      email: email,
      role: role,
      usedTokens: readInt(tokens['totalTokens']),
      periodStartUtc: DateTime.tryParse(
        json['periodStartUtc'] as String? ?? '',
      ),
      periodEndUtc: DateTime.tryParse(json['periodEndUtc'] as String? ?? ''),
      updatedAtUtc: DateTime.now().toUtc(),
    );
  }

  // Claims are used for display only; server authorization remains authoritative.
  Future<Map<String, String>> _identityClaims(String ownerId) async {
    final tokens = await _client.tokenStorage?.readTokens();
    if (tokens == null) return {};
    try {
      final parts = tokens.accessToken.split('.');
      if (parts.length != 3) return {};
      final claims =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      const claimPrefix =
          'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/';
      final subject = claims['sub'] ?? claims['${claimPrefix}nameidentifier'];
      if (subject != ownerId) return {};
      String? read(String key, String fallback) {
        final value = claims[key] ?? claims[fallback];
        if (value is String && value.trim().isNotEmpty) return value.trim();
        if (value is List) {
          final values = value.whereType<String>().where(
            (v) => v.trim().isNotEmpty,
          );
          if (values.isNotEmpty) return values.join(', ');
        }
        return null;
      }

      return {
        if (read('name', '${claimPrefix}name') case final String name)
          'name': name,
        if (read('email', '${claimPrefix}emailaddress') case final String email)
          'email': email,
        if (read(
              'role',
              'http://schemas.microsoft.com/ws/2008/06/identity/claims/role',
            )
            case final String role)
          'role': role,
      };
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }
}
