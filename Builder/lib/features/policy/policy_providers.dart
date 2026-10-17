import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/storage_providers.dart';
import 'domain/policy_repository.dart';
import 'infrastructure/persistent_policy_repository.dart';

final persistentPolicyRepositoryProvider = Provider<PolicyRepository?>((ref) {
  final db = ref.watch(storageDatabaseProvider);
  if (db == null) return null;
  return PersistentPolicyRepository(database: db);
});

final policyRepositoryProvider = Provider<PolicyRepository>((ref) {
  final persistent = ref.watch(persistentPolicyRepositoryProvider);
  return persistent ?? InMemoryPolicyRepository();
});
