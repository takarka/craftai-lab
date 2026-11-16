import '../domain/lab_agent.dart';
import 'agents_cache.dart';
import 'lab_api_client.dart';

class AgentsRepository {
  AgentsRepository({required this.api, required this.cache});
  final LabApiClient api;
  final AgentsCache cache;
  List<LabAgent> _agents = const [];

  Future<AgentsSnapshot> load() async {
    try {
      _agents = List.unmodifiable(await api.listAgents());
      await cache.replace(_agents);
      return AgentsSnapshot(_agents);
    } on LabApiException catch (error) {
      if (!error.isConnectionFailure) rethrow;
      final cached = await cache.read();
      if (cached == null) rethrow;
      _agents = List.unmodifiable(cached);
      return AgentsSnapshot(_agents, offline: true);
    }
  }

  Future<LabAgent> _save(Future<LabAgent> operation) async {
    final agent = await operation;
    _agents = List.unmodifiable([
      ..._agents.where((item) => item.id != agent.id),
      agent,
    ]);
    await cache.replace(_agents);
    return agent;
  }

  Future<LabAgent> create(Map<String, dynamic> config) =>
      _save(api.create(config));
  Future<LabAgent> update(String id, Map<String, dynamic> changes) =>
      _save(api.update(id, changes));
  Future<LabAgent> copy(LabAgent agent, String name) =>
      _save(api.copy(agent.id, name));
  Future<LabAgent> reset(String id) async {
    final result = await _save(api.reset(id));
    await cache.clearAgentData(id);
    return result;
  }

  Future<void> delete(String id) async {
    await api.delete(id);
    _agents = List.unmodifiable(_agents.where((agent) => agent.id != id));
    await cache.clearAgentData(id);
    await cache.replace(_agents);
    if (await cache.selected() == id) await cache.select(null);
  }
}
