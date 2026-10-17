import 'package:flutter/foundation.dart';

@immutable
final class PolicyAcknowledgment {
  const PolicyAcknowledgment({
    required this.ownerId,
    required this.policyId,
    required this.policyVersion,
    required this.acknowledgedAtUtc,
  });

  final String ownerId;
  final String policyId;
  final String policyVersion;
  final DateTime acknowledgedAtUtc;
}

abstract interface class PolicyRepository {
  Future<bool> isPolicyAcknowledged({
    required String ownerId,
    required String policyId,
  });

  Future<PolicyAcknowledgment?> getAcknowledgment({
    required String ownerId,
    required String policyId,
  });

  Future<void> acknowledgePolicy({
    required String ownerId,
    required String policyId,
    required String policyVersion,
  });
}
