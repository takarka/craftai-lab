class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    DateTime? refreshExpiresAtUtc,
    this.tokenType = 'Bearer',
    required this.expiresAtUtc,
  }) : refreshExpiresAtUtc = refreshExpiresAtUtc ?? expiresAtUtc;

  final String accessToken;
  final String refreshToken;
  final DateTime refreshExpiresAtUtc;
  final String tokenType;
  final DateTime expiresAtUtc;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAtUtc);

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'refresh_expires_at_utc': refreshExpiresAtUtc.toIso8601String(),
    'token_type': tokenType,
    'expires_at_utc': expiresAtUtc.toIso8601String(),
  };

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    final access = json['access_token'] as String?;
    final refresh = json['refresh_token'] as String?;
    final expires = json['expires_at_utc'] as String?;
    final refreshExpires = json['refresh_expires_at_utc'] as String?;
    if (access == null || refresh == null || expires == null) {
      throw const FormatException('Invalid auth tokens JSON representation.');
    }
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresAtUtc: DateTime.parse(expires).toUtc(),
      refreshExpiresAtUtc: refreshExpires == null
          ? DateTime.parse(expires).toUtc()
          : DateTime.parse(refreshExpires).toUtc(),
    );
  }
}
