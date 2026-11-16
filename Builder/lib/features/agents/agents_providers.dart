import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/network/api_http_client.dart';
import '../../core/storage/storage_providers.dart';
import '../session/session_providers.dart';
import '../session/session_repository.dart';
import 'domain/lab_agent.dart';
import 'infrastructure/agents_cache.dart';
import 'infrastructure/agents_repository.dart';
import 'infrastructure/lab_api_client.dart';

final agentsRepositoryProvider = Provider.autoDispose
    .family<AgentsRepository, String>((ref, ownerId) {
      final config = ref.watch(appConfigProvider);
      final baseUri = config?.apiBaseUri;
      if (baseUri == null) throw const LabApiException('api.not-configured');
      final client = createApiHttpClient(config);
      ref.onDispose(client.close);
      final db = ref.watch(storageDatabaseProvider);
      return AgentsRepository(
        api: LabApiClient(
          baseUri: baseUri,
          client: client,
          tokens: ref.watch(secureTokenStorageProvider),
          ownerId: ownerId,
        ),
        cache: db == null
            ? MemoryAgentsCache()
            : SqliteAgentsCache(
                database: db,
                ownerId: ownerId,
                keys: ref.watch(secureKeyStorageProvider),
                installationId: ref.watch(installationIdProvider),
              ),
      );
    }, retry: (count, error) => null);

final agentsProvider = AsyncNotifierProvider.autoDispose
    .family<AgentsController, AgentsSnapshot, String>(
      AgentsController.new,
      retry: (count, error) => null,
    );

class AgentsController extends AsyncNotifier<AgentsSnapshot> {
  AgentsController(this.ownerId);
  final String ownerId;
  bool busy = false;
  bool _active = true;
  @override
  Future<AgentsSnapshot> build() {
    _active = true;
    ref.onDispose(() => _active = false);
    return ref.watch(agentsRepositoryProvider(ownerId)).load();
  }

  Future<void> refresh() async {
    if (busy) return;
    busy = true;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () => ref.read(agentsRepositoryProvider(ownerId)).load(),
    );
    if (_active) state = next;
    busy = false;
  }

  Future<T> mutate<T>(Future<T> Function(AgentsRepository) action) async {
    if (busy || state.asData == null || state.asData!.value.offline) {
      throw const LabApiException('agents.busy');
    }
    busy = true;
    final repository = ref.read(agentsRepositoryProvider(ownerId));
    try {
      final result = await action(repository);
      final snapshot = await repository.load();
      if (_active) state = AsyncData(snapshot);
      return result;
    } catch (_) {
      // No POST retry after an ambiguous response. Reconcile the list only.
      final next = await AsyncValue.guard(repository.load);
      if (_active) state = next;
      rethrow;
    } finally {
      busy = false;
    }
  }
}

final currentAgentIdProvider = AsyncNotifierProvider.autoDispose
    .family<CurrentAgentId, String?, String>(
      CurrentAgentId.new,
      retry: (count, error) => null,
    );

class CurrentAgentId extends AsyncNotifier<String?> {
  CurrentAgentId(this.ownerId);
  final String ownerId;
  @override
  Future<String?> build() async {
    final session = ref.watch(sessionProvider).asData?.value;
    if (session is! AuthenticatedSession || session.ownerId != ownerId) {
      return null;
    }
    final snapshot = await ref.watch(agentsProvider(ownerId).future);
    final cache = ref.watch(agentsRepositoryProvider(ownerId)).cache;
    final id = await cache.selected();
    return snapshot.agents.any((agent) => agent.id == id) ? id : null;
  }

  Future<void> select(String? id) async {
    final agents = await ref.read(agentsProvider(ownerId).future);
    if (id != null && !agents.agents.any((agent) => agent.id == id)) {
      throw const LabApiException('agents.not-found');
    }
    await ref.read(agentsRepositoryProvider(ownerId)).cache.select(id);
    if (ref.mounted) state = AsyncData(id);
  }
}
