import '../../models/infrastructure/craft_ai_client.dart';

/// Wire values retain wall-clock dates and IANA zones without device conversion.
class BuilderCalendarClient {
  const BuilderCalendarClient(this.api);
  final CraftAiClient api;
  static const _root = '/builder/calendar';

  Future<Map<String, dynamic>> occurrences(String from, String to) =>
      api.getJson(
        Uri(
          path: '$_root/events',
          queryParameters: {'from': from, 'to': to},
        ).toString(),
      );

  Future<Map<String, dynamic>> event(String id) =>
      api.getJson('$_root/events/${Uri.encodeComponent(id)}');

  /// Keep the same key when retrying an uncertain create result.
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> input, {
    required String idempotencyKey,
  }) => api.requestJson(
    'POST',
    '$_root/events',
    body: input,
    headers: {'Idempotency-Key': idempotencyKey},
  );

  Future<Map<String, dynamic>> replace(
    String id,
    int version,
    Map<String, dynamic> input,
  ) => api.requestJson(
    'PUT',
    '$_root/events/${Uri.encodeComponent(id)}',
    body: input,
    headers: {'If-Match': '"$version"'},
  );

  Future<void> delete(String id, {String? followingFrom}) async {
    await api.requestJson(
      'DELETE',
      Uri(
        path: '$_root/events/${Uri.encodeComponent(id)}',
        queryParameters: {
          'scope': followingFrom == null ? 'all' : 'following',
          if (followingFrom != null) 'from': followingFrom,
        },
      ).toString(),
    );
  }

  Future<Map<String, dynamic>> overrideOccurrence(
    String id,
    String date,
    Map<String, dynamic> input,
  ) => api.requestJson(
    'PUT',
    '$_root/events/${Uri.encodeComponent(id)}/occurrences/${Uri.encodeComponent(date)}',
    body: input,
  );

  Future<Map<String, dynamic>> changes({String? cursor}) => api.getJson(
    Uri(
      path: '$_root/changes',
      queryParameters: {if (cursor != null) 'cursor': cursor},
    ).toString(),
  );
}
