import '../../onboarding/domain/assistant_setup.dart';

class TeacherPreferences {
  TeacherPreferences({required this.setup, required this.uiLanguage});
  final AssistantSetup setup;
  final String uiLanguage;
}

/// Confirmed account data only. A missing limit is not an unlimited quota.
class AccountSnapshot {
  AccountSnapshot({
    required this.ownerId,
    required this.updatedAtUtc,
    this.name,
    this.email,
    this.usedTokens,
    this.tokenLimit,
    this.periodStartUtc,
    this.periodEndUtc,
  }) {
    if (ownerId.isEmpty ||
        (usedTokens != null && usedTokens! < 0) ||
        (tokenLimit != null && tokenLimit! <= 0)) {
      throw const FormatException('Invalid account snapshot');
    }
  }

  final String ownerId;
  final String? name;
  final String? email;
  final int? usedTokens;
  final int? tokenLimit;
  final DateTime? periodStartUtc;
  final DateTime? periodEndUtc;
  final DateTime updatedAtUtc;

  Map<String, dynamic> toJson() => {
    'ownerId': ownerId,
    'name': name,
    'email': email,
    'usedTokens': usedTokens,
    'tokenLimit': tokenLimit,
    'periodStartUtc': periodStartUtc?.toIso8601String(),
    'periodEndUtc': periodEndUtc?.toIso8601String(),
    'updatedAtUtc': updatedAtUtc.toIso8601String(),
  };

  factory AccountSnapshot.fromJson(Map<String, dynamic> json) =>
      AccountSnapshot(
        ownerId: json['ownerId'] as String,
        name: json['name'] as String?,
        email: json['email'] as String?,
        usedTokens: json['usedTokens'] as int?,
        tokenLimit: json['tokenLimit'] as int?,
        periodStartUtc: DateTime.tryParse(
          json['periodStartUtc'] as String? ?? '',
        ),
        periodEndUtc: DateTime.tryParse(json['periodEndUtc'] as String? ?? ''),
        updatedAtUtc: DateTime.parse(json['updatedAtUtc'] as String),
      );
}

/// Client port. No HTTP path is assumed until B06/B07 publish a contract.
abstract interface class ProfileAccountGateway {
  bool get isAvailable;
  Future<AccountSnapshot> load(String ownerId);
}

class UnavailableProfileAccountGateway implements ProfileAccountGateway {
  const UnavailableProfileAccountGateway();
  @override
  bool get isAvailable => false;
  @override
  Future<AccountSnapshot> load(String ownerId) async =>
      throw StateError('Account API is not connected');
}

class ProfileAccountState {
  const ProfileAccountState({
    this.snapshot,
    this.cached = false,
    this.unavailable = false,
  });
  final AccountSnapshot? snapshot;
  final bool cached;
  final bool unavailable;
}
