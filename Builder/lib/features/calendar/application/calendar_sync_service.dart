import '../../models/infrastructure/craft_ai_client.dart';
import '../domain/calendar_models.dart';
import '../domain/recurrence_expander.dart';
import '../infrastructure/builder_calendar_client.dart';
import '../infrastructure/calendar_repository.dart';

/// True when a failed create may still have reached the server, so the same
/// `Idempotency-Key` must be replayed instead of discarding the draft.
bool isUncertainCalendarFailure(Object error) {
  if (error is! CraftAiException) return true;
  final status = error.statusCode;
  if (status == null) return true;
  if (status == 401 || status == 403 || status == 408 || status == 429) {
    return true;
  }
  return status >= 500;
}

enum CalendarCreateOutcome {
  saved,

  /// Outcome unknown: stored and replayed later with the same key.
  queued,
  rejected,
  authRequired,
}

class CalendarSyncResult {
  const CalendarSyncResult({this.rejected = const []});

  /// Queued creates that the server definitively refused (and were dropped).
  final List<PendingCalendarCreate> rejected;
}

/// Pulls server changes into the owner-scoped cache. Server data is never
/// replaced by fixtures: on failure the cache stays as it was.
class CalendarSyncService {
  const CalendarSyncService({required this.client, required this.repository});
  final BuilderCalendarClient client;
  final CalendarRepository repository;

  /// Persists the draft first, so a lost answer is replayed with the same
  /// `Idempotency-Key` instead of creating a duplicate or losing the event.
  Future<CalendarCreateOutcome> create(
    String ownerId,
    Map<String, dynamic> input, {
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? CraftAiClient.generateRequestId();
    await repository.addPendingCreate(
      ownerId,
      PendingCalendarCreate(
        key: key,
        input: input,
        createdAtUtc: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    try {
      await client.create(input, idempotencyKey: key);
      await repository.removePendingCreate(ownerId, key);
      return CalendarCreateOutcome.saved;
    } catch (error) {
      if (error is CraftAiAuthException) return CalendarCreateOutcome.authRequired;
      if (isUncertainCalendarFailure(error)) return CalendarCreateOutcome.queued;
      await repository.removePendingCreate(ownerId, key);
      return CalendarCreateOutcome.rejected;
    }
  }

  /// Replays queued creates, then downloads changes after the stored cursor.
  Future<CalendarSyncResult> sync(String ownerId) async {
    final rejected = <PendingCalendarCreate>[];
    for (final pending in await repository.pendingCreates(ownerId)) {
      try {
        await client.create(pending.input, idempotencyKey: pending.key);
        await repository.removePendingCreate(ownerId, pending.key);
      } catch (error) {
        if (isUncertainCalendarFailure(error)) {
          if (error is CraftAiAuthException) rethrow;
          continue;
        }
        await repository.removePendingCreate(ownerId, pending.key);
        rejected.add(pending);
      }
    }

    var cursor = await repository.cursor(ownerId);
    var replaceAll = cursor == null || cursor.isEmpty;
    while (true) {
      final page = await client.changes(cursor: cursor);
      await repository.applyChanges(ownerId, page, replaceAll: replaceAll);
      cursor = page.nextCursor;
      replaceAll = false;
      if (!page.hasMore) break;
    }
    return CalendarSyncResult(rejected: rejected);
  }

  /// Fetches the server's occurrences for `[from, to]` and records which
  /// series dates were canceled or moved (overrides are not part of events).
  Future<void> refreshRange(String ownerId, String from, String to) async {
    final served = await client.occurrences(from, to);
    final events = await repository.events(ownerId);
    final known = {for (final e in events) e.id};
    final reconciled = RecurrenceExpander.reconcile(
      events,
      from,
      to,
      served.where((o) => known.contains(o.eventId)),
    );
    await repository.reconcileOverrides(
      ownerId,
      reconciled.set,
      reconciled.clearKeys,
    );
  }
}
