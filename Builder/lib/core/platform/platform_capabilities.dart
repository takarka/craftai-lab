import 'package:flutter/foundation.dart';

/// A platform candidate is not a permission or a working native adapter.
enum CapabilitySupport { unsupported, requiresNativeVerification }

class PlatformCapabilities {
  const PlatformCapabilities({required this.nativeActions});

  factory PlatformCapabilities.current() => PlatformCapabilities.forPlatform(
    platform: defaultTargetPlatform,
    isWeb: kIsWeb,
  );

  factory PlatformCapabilities.forPlatform({
    required TargetPlatform platform,
    required bool isWeb,
  }) {
    final mobile =
        !isWeb &&
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
    return PlatformCapabilities(
      nativeActions: mobile
          ? CapabilitySupport.requiresNativeVerification
          : CapabilitySupport.unsupported,
    );
  }

  final CapabilitySupport nativeActions;
}
