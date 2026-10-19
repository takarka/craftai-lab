import '../../models/infrastructure/craft_ai_client.dart';

typedef Json = Map<String, dynamic>;

/// The server owns timing, ownership, execution and retention. No local AI timer.
class BuilderSchedulesClient {
  const BuilderSchedulesClient(this.api);
  final CraftAiClient api;
  String _id(String id) => Uri.encodeComponent(id);

  Future<List<Json>> list() async =>
      _items(await api.getJson('/builder/schedules'));

  Future<Json> save(String template, Json input, {int? version}) =>
      api.requestJson(
        'PUT',
        '/builder/schedules/${_id(template)}',
        body: input,
        headers: {if (version != null) 'If-Match': '"$version"'},
      );

  Future<Json> pause(String id, {required bool paused}) => api.requestJson(
    'POST',
    '/builder/schedules/${_id(id)}/${paused ? 'pause' : 'resume'}',
  );

  Future<void> delete(String id) async {
    await api.requestJson('DELETE', '/builder/schedules/${_id(id)}');
  }

  // This operation is not idempotent on the server: never retry automatically.
  Future<Json> runNow(String id) =>
      api.requestJson('POST', '/builder/schedules/${_id(id)}/run-now');

  Future<Json> runs(String id, {String? cursor}) => api.getJson(
    Uri(
      path: '/builder/schedules/${_id(id)}/runs',
      queryParameters: {if (cursor != null) 'cursor': cursor},
    ).toString(),
  );

  Future<Json> run(String id) => api.getJson('/builder/runs/${_id(id)}');

  Future<void> deleteRun(String id) async {
    await api.requestJson('DELETE', '/builder/runs/${_id(id)}');
  }

  Future<void> registerDevice(String installationId, Json input) async {
    await api.requestJson(
      'PUT',
      '/builder/devices/${_id(installationId)}',
      body: input,
    );
  }

  Future<void> revokeDevice(String installationId) async {
    await api.requestJson('DELETE', '/builder/devices/${_id(installationId)}');
  }

  static List<Json> _items(Json json) => [
    for (final item in json['items'] as List) Json.from(item as Map),
  ];
}
