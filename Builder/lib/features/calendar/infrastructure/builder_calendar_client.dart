import '../../models/infrastructure/craft_ai_client.dart';
import '../domain/calendar_models.dart';

/// Wire values retain wall-clock dates and IANA zones without device conversion.
class BuilderCalendarClient {
  const BuilderCalendarClient(this.api);
  final CraftAiClient api;
  static const _root = '/builder/calendar';

  Future<List<CalendarOccurrence>> occurrences(String from, String to) async {
    final json = await api.getJson(
      Uri(
        path: '$_root/events',
        queryParameters: {'from': from, 'to': to},
      ).toString(),
    );
    return [
      for (final item in json['items'] as List)
        CalendarOccurrence.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<CalendarEvent> event(String id) async => CalendarEvent.fromJson(
    await api.getJson('$_root/events/${Uri.encodeComponent(id)}'),
  );

  /// Keep the same key when retrying an uncertain create result.
  Future<void> create(
    Map<String, dynamic> input, {
    required String idempotencyKey,
  }) async {
    await api.requestJson(
      'POST',
      '$_root/events',
      body: input,
      headers: {'Idempotency-Key': idempotencyKey},
    );
  }

  Future<void> replace(
    String id,
    int version,
    Map<String, dynamic> input,
  ) async {
    await api.requestJson(
      'PUT',
      '$_root/events/${Uri.encodeComponent(id)}',
      body: input,
      headers: {'If-Match': '"$version"'},
    );
  }

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

  Future<void> overrideOccurrence(
    String id,
    String date,
    Map<String, dynamic> input,
  ) async {
    await api.requestJson(
      'PUT',
      '$_root/events/${Uri.encodeComponent(id)}/occurrences/${Uri.encodeComponent(date)}',
      body: input,
    );
  }

  Future<CalendarChangesPage> changes({String? cursor}) async =>
      CalendarChangesPage.fromJson(
        await api.getJson(
          Uri(
            path: '$_root/changes',
            queryParameters: {
              if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
            },
          ).toString(),
        ),
      );
}
