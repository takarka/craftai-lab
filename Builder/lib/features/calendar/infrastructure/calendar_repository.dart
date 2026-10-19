import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../domain/calendar_models.dart';

/// Owner-scoped offline cache of the server calendar.
abstract class CalendarRepository {
  Future<List<CalendarEvent>> events(String ownerId);
  Future<List<OccurrenceOverride>> overrides(String ownerId);
  Future<String?> cursor(String ownerId);
  Future<DateTime?> syncedAt(String ownerId);

  /// Applies one `changes` page and stores its cursor atomically. With
  /// [replaceAll] the cache of [ownerId] is cleared first (full download).
  Future<void> applyChanges(
    String ownerId,
    CalendarChangesPage page, {
    required bool replaceAll,
  });

  /// Stores [set] and drops [clearKeys] (`eventId|yyyy-MM-dd`).
  Future<void> reconcileOverrides(
    String ownerId,
    Iterable<OccurrenceOverride> set,
    Iterable<String> clearKeys,
  );

  Future<List<PendingCalendarCreate>> pendingCreates(String ownerId);
  Future<void> addPendingCreate(String ownerId, PendingCalendarCreate pending);
  Future<void> removePendingCreate(String ownerId, String key);
}

class InMemoryCalendarRepository implements CalendarRepository {
  final _events = <String, Map<String, CalendarEvent>>{};
  final _overrides = <String, Map<String, OccurrenceOverride>>{};
  final _cursors = <String, String>{};
  final _synced = <String, DateTime>{};
  final _pending = <String, Map<String, PendingCalendarCreate>>{};

  @override
  Future<List<CalendarEvent>> events(String ownerId) async =>
      List.of(_events[ownerId]?.values ?? const []);

  @override
  Future<List<OccurrenceOverride>> overrides(String ownerId) async =>
      List.of(_overrides[ownerId]?.values ?? const []);

  @override
  Future<String?> cursor(String ownerId) async => _cursors[ownerId];

  @override
  Future<DateTime?> syncedAt(String ownerId) async => _synced[ownerId];

  @override
  Future<void> applyChanges(
    String ownerId,
    CalendarChangesPage page, {
    required bool replaceAll,
  }) async {
    final events = _events.putIfAbsent(ownerId, () => {});
    final overrides = _overrides.putIfAbsent(ownerId, () => {});
    if (replaceAll) {
      events.clear();
      overrides.clear();
    }
    for (final change in page.items) {
      if (change.isDelete) {
        events.remove(change.eventId);
        overrides.removeWhere((_, o) => o.eventId == change.eventId);
      } else {
        events[change.eventId] = change.event!;
      }
    }
    _cursors[ownerId] = page.nextCursor;
    _synced[ownerId] = DateTime.now().toUtc();
  }

  @override
  Future<void> reconcileOverrides(
    String ownerId,
    Iterable<OccurrenceOverride> set,
    Iterable<String> clearKeys,
  ) async {
    final overrides = _overrides.putIfAbsent(ownerId, () => {});
    for (final key in clearKeys) {
      overrides.remove(key);
    }
    for (final o in set) {
      overrides['${o.eventId}|${o.date}'] = o;
    }
  }

  @override
  Future<List<PendingCalendarCreate>> pendingCreates(String ownerId) async =>
      List.of(_pending[ownerId]?.values ?? const []);

  @override
  Future<void> addPendingCreate(
    String ownerId,
    PendingCalendarCreate pending,
  ) async => _pending.putIfAbsent(ownerId, () => {})[pending.key] = pending;

  @override
  Future<void> removePendingCreate(String ownerId, String key) async =>
      _pending[ownerId]?.remove(key);
}

class PersistentCalendarRepository implements CalendarRepository {
  PersistentCalendarRepository({required this.database});
  final StorageDatabase database;

  Future<Database> get _db async {
    if (!database.isOpen) await database.open();
    return database.db;
  }

  @override
  Future<List<CalendarEvent>> events(String ownerId) async {
    final rows = await (await _db).query(
      StorageSchemaV1.tableCalendarEvents,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    return [
      for (final row in rows)
        CalendarEvent.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(row['event_json'] as String) as Map,
          ),
        ),
    ];
  }

  @override
  Future<List<OccurrenceOverride>> overrides(String ownerId) async {
    final rows = await (await _db).query(
      StorageSchemaV1.tableCalendarOverrides,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    return rows.map(OccurrenceOverride.fromMap).toList();
  }

  Future<Map<String, Object?>?> _syncRow(String ownerId) async {
    final rows = await (await _db).query(
      StorageSchemaV1.tableCalendarSync,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<String?> cursor(String ownerId) async =>
      (await _syncRow(ownerId))?['cursor'] as String?;

  @override
  Future<DateTime?> syncedAt(String ownerId) async {
    final value = (await _syncRow(ownerId))?['synced_at_utc'] as String?;
    return value == null ? null : DateTime.parse(value);
  }

  @override
  Future<void> applyChanges(
    String ownerId,
    CalendarChangesPage page, {
    required bool replaceAll,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (replaceAll) {
        for (final table in [
          StorageSchemaV1.tableCalendarEvents,
          StorageSchemaV1.tableCalendarOverrides,
        ]) {
          await txn.delete(table, where: 'owner_id = ?', whereArgs: [ownerId]);
        }
      }
      for (final change in page.items) {
        if (change.isDelete) {
          await txn.delete(
            StorageSchemaV1.tableCalendarEvents,
            where: 'owner_id = ? AND id = ?',
            whereArgs: [ownerId, change.eventId],
          );
          await txn.delete(
            StorageSchemaV1.tableCalendarOverrides,
            where: 'owner_id = ? AND event_id = ?',
            whereArgs: [ownerId, change.eventId],
          );
        } else {
          final event = change.event!;
          await txn.insert(StorageSchemaV1.tableCalendarEvents, {
            'owner_id': ownerId,
            'id': event.id,
            'version': event.version,
            'event_json': jsonEncode(event.toJson()),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await txn.insert(StorageSchemaV1.tableCalendarSync, {
        'owner_id': ownerId,
        'cursor': page.nextCursor,
        'synced_at_utc': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> reconcileOverrides(
    String ownerId,
    Iterable<OccurrenceOverride> set,
    Iterable<String> clearKeys,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final key in clearKeys) {
        final split = key.indexOf('|');
        await txn.delete(
          StorageSchemaV1.tableCalendarOverrides,
          where: 'owner_id = ? AND event_id = ? AND occurrence_date = ?',
          whereArgs: [ownerId, key.substring(0, split), key.substring(split + 1)],
        );
      }
      for (final o in set) {
        await txn.insert(StorageSchemaV1.tableCalendarOverrides, {
          'owner_id': ownerId,
          'event_id': o.eventId,
          'occurrence_date': o.date,
          'canceled': o.canceled ? 1 : 0,
          'title': o.title,
          'notes': o.notes,
          'start_local': o.start,
          'end_local': o.end,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<List<PendingCalendarCreate>> pendingCreates(String ownerId) async {
    final rows = await (await _db).query(
      StorageSchemaV1.tableCalendarPending,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'created_at_utc',
    );
    return [
      for (final row in rows)
        PendingCalendarCreate(
          key: row['idempotency_key'] as String,
          input: Map<String, dynamic>.from(
            jsonDecode(row['input_json'] as String) as Map,
          ),
          createdAtUtc: row['created_at_utc'] as String,
        ),
    ];
  }

  @override
  Future<void> addPendingCreate(
    String ownerId,
    PendingCalendarCreate pending,
  ) async {
    await (await _db).insert(StorageSchemaV1.tableCalendarPending, {
      'owner_id': ownerId,
      'idempotency_key': pending.key,
      'input_json': jsonEncode(pending.input),
      'created_at_utc': pending.createdAtUtc,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> removePendingCreate(String ownerId, String key) async {
    await (await _db).delete(
      StorageSchemaV1.tableCalendarPending,
      where: 'owner_id = ? AND idempotency_key = ?',
      whereArgs: [ownerId, key],
    );
  }
}
