import 'package:sqflite/sqflite.dart';

import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../domain/memory_models.dart';
import '../domain/memory_repository.dart';

/// SQLite-backed persistent memory repository for classroom facts (F13-01, F13-06).
class PersistentMemoryRepository implements MemoryRepository {
  final StorageDatabase database;

  // In-memory candidate suggestions (F13-03: candidate facts are ephemeral until saved)
  final Map<String, List<MemoryCandidateFact>> _candidates = {};

  PersistentMemoryRepository({required this.database});

  Future<void> _ensureOpen() async {
    if (!database.isOpen) {
      await database.open();
    }
  }

  Future<Database> get _db async {
    await _ensureOpen();
    return database.db;
  }

  @override
  Future<List<MemoryFact>> getFacts({
    required String ownerId,
    bool? enabledOnly,
  }) async {
    final db = await _db;
    final whereClauses = <String>['owner_id = ?'];
    final whereArgs = <dynamic>[ownerId];

    if (enabledOnly == true) {
      whereClauses.add('is_enabled = 1');
    }

    final rows = await db.query(
      StorageSchemaV1.tableMemoryFacts,
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'created_at_utc ASC',
    );

    return rows.map((r) => MemoryFact.fromMap(r)).toList();
  }

  @override
  Future<MemoryFact> addFact({
    required String ownerId,
    required String factText,
    MemoryFactSource source = MemoryFactSource.manual,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final id =
        'fact_${now.millisecondsSinceEpoch}_${factText.hashCode.abs() % 10000}';

    final fact = MemoryFact(
      id: id,
      ownerId: ownerId,
      factText: factText.trim(),
      source: source,
      isEnabled: true,
      createdAtUtc: now,
      updatedAtUtc: now,
    );

    await db.transaction((txn) async {
      await txn.insert(
        StorageSchemaV1.tableMemoryFacts,
        fact.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Bump assistant configuration version timestamp
      await _touchAssistantConfig(txn, ownerId, now);
    });

    return fact;
  }

  @override
  Future<MemoryFact> updateFact({
    required String id,
    required String factText,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();

    final existingRows = await db.query(
      StorageSchemaV1.tableMemoryFacts,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (existingRows.isEmpty) {
      throw StateError('Fact not found: $id');
    }

    final existing = MemoryFact.fromMap(existingRows.first);
    final updated = existing.copyWith(
      factText: factText.trim(),
      updatedAtUtc: now,
    );

    await db.transaction((txn) async {
      await txn.update(
        StorageSchemaV1.tableMemoryFacts,
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [id],
      );
      await _touchAssistantConfig(txn, existing.ownerId, now);
    });

    return updated;
  }

  @override
  Future<void> toggleFact({required String id, required bool isEnabled}) async {
    final db = await _db;
    final now = DateTime.now().toUtc();

    final existingRows = await db.query(
      StorageSchemaV1.tableMemoryFacts,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (existingRows.isEmpty) return;

    final existing = MemoryFact.fromMap(existingRows.first);

    await db.transaction((txn) async {
      await txn.update(
        StorageSchemaV1.tableMemoryFacts,
        {
          'is_enabled': isEnabled ? 1 : 0,
          'updated_at_utc': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _touchAssistantConfig(txn, existing.ownerId, now);
    });
  }

  @override
  Future<void> deleteFact({required String id, required String ownerId}) async {
    // Physical deletion per ADR-02 (F13-06, F13-12)
    final db = await _db;
    final now = DateTime.now().toUtc();

    await db.transaction((txn) async {
      await txn.delete(
        StorageSchemaV1.tableMemoryFacts,
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, ownerId],
      );
      await _touchAssistantConfig(txn, ownerId, now);
    });
  }

  @override
  Future<List<MemoryCandidateFact>> getSuggestedFacts({
    required String ownerId,
  }) async {
    final list = _candidates[ownerId];
    if (list != null) return List.unmodifiable(list);

    // Initial default candidate facts for demonstration and learning
    final defaultCandidates = [
      MemoryCandidateFact(
        id: 'cand_${ownerId}_1',
        ownerId: ownerId,
        factText: 'Ученики сидят парами за 12 двухместными партами',
        rationale: 'Обнаружено в диалоге о рассадке в кабинете',
        suggestedAtUtc: DateTime.now().toUtc(),
      ),
    ];
    _candidates[ownerId] = defaultCandidates;
    return List.unmodifiable(defaultCandidates);
  }

  @override
  Future<MemoryCandidateFact> addSuggestedFact({
    required String ownerId,
    required String factText,
    String? rationale,
  }) async {
    final candidate = MemoryCandidateFact(
      id: 'cand_${DateTime.now().millisecondsSinceEpoch}_${factText.hashCode.abs() % 1000}',
      ownerId: ownerId,
      factText: factText.trim(),
      rationale: rationale,
      suggestedAtUtc: DateTime.now().toUtc(),
    );

    final list = _candidates.putIfAbsent(ownerId, () => []);
    list.add(candidate);
    return candidate;
  }

  @override
  Future<void> dismissSuggestedFact({
    required String ownerId,
    required String candidateId,
  }) async {
    _candidates[ownerId]?.removeWhere((c) => c.id == candidateId);
  }

  @override
  Future<MemoryFact> acceptSuggestedFact({
    required String ownerId,
    required String candidateId,
  }) async {
    final candidates = _candidates[ownerId] ?? [];
    final idx = candidates.indexWhere((c) => c.id == candidateId);
    if (idx == -1) {
      throw StateError('Suggested fact candidate not found: $candidateId');
    }
    final candidate = candidates[idx];
    candidates.removeAt(idx);

    return addFact(
      ownerId: ownerId,
      factText: candidate.factText,
      source: MemoryFactSource.suggested,
    );
  }

  @override
  Future<List<MemoryFact>> loadEducationalPracticePresets({
    required String ownerId,
  }) async {
    final presets = [
      'В 7 «Б» классе 24 ученика',
      'Длительность одного урока составляет 40 минут',
      'Профильный предмет класса — углубленная математика',
    ];

    final created = <MemoryFact>[];
    for (final text in presets) {
      final fact = await addFact(
        ownerId: ownerId,
        factText: text,
        source: MemoryFactSource.manual,
      );
      created.add(fact);
    }
    return created;
  }

  Future<void> _touchAssistantConfig(
    DatabaseExecutor txn,
    String ownerId,
    DateTime now,
  ) async {
    try {
      await txn.rawUpdate(
        '''
        UPDATE ${StorageSchemaV1.tableAssistantConfigurations}
        SET updated_at_utc = ?
        WHERE owner_id = ?
        ''',
        [now.toIso8601String(), ownerId],
      );
    } catch (_) {
      // Configuration might not exist yet in detached tests
    }
  }
}

/// In-memory mock implementation for fast isolated unit tests.
class InMemoryMemoryRepository implements MemoryRepository {
  final Map<String, List<MemoryFact>> _facts = {};
  final Map<String, List<MemoryCandidateFact>> _candidates = {};

  @override
  Future<List<MemoryFact>> getFacts({
    required String ownerId,
    bool? enabledOnly,
  }) async {
    final list = _facts[ownerId] ?? [];
    if (enabledOnly == true) {
      return list.where((f) => f.isEnabled).toList();
    }
    return List.unmodifiable(list);
  }

  @override
  Future<MemoryFact> addFact({
    required String ownerId,
    required String factText,
    MemoryFactSource source = MemoryFactSource.manual,
  }) async {
    final now = DateTime.now().toUtc();
    final fact = MemoryFact(
      id: 'fact_${now.millisecondsSinceEpoch}_${_facts.length}',
      ownerId: ownerId,
      factText: factText.trim(),
      source: source,
      isEnabled: true,
      createdAtUtc: now,
      updatedAtUtc: now,
    );

    final list = _facts.putIfAbsent(ownerId, () => []);
    list.add(fact);
    return fact;
  }

  @override
  Future<MemoryFact> updateFact({
    required String id,
    required String factText,
  }) async {
    for (final entry in _facts.entries) {
      final idx = entry.value.indexWhere((f) => f.id == id);
      if (idx != -1) {
        final existing = entry.value[idx];
        final updated = existing.copyWith(
          factText: factText.trim(),
          updatedAtUtc: DateTime.now().toUtc(),
        );
        entry.value[idx] = updated;
        return updated;
      }
    }
    throw StateError('Fact not found: $id');
  }

  @override
  Future<void> toggleFact({required String id, required bool isEnabled}) async {
    for (final list in _facts.values) {
      final idx = list.indexWhere((f) => f.id == id);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(
          isEnabled: isEnabled,
          updatedAtUtc: DateTime.now().toUtc(),
        );
        return;
      }
    }
  }

  @override
  Future<void> deleteFact({required String id, required String ownerId}) async {
    _facts[ownerId]?.removeWhere((f) => f.id == id);
  }

  @override
  Future<List<MemoryCandidateFact>> getSuggestedFacts({
    required String ownerId,
  }) async {
    return List.unmodifiable(_candidates[ownerId] ?? []);
  }

  @override
  Future<MemoryCandidateFact> addSuggestedFact({
    required String ownerId,
    required String factText,
    String? rationale,
  }) async {
    final candidate = MemoryCandidateFact(
      id: 'cand_${DateTime.now().millisecondsSinceEpoch}_${_candidates.length}',
      ownerId: ownerId,
      factText: factText.trim(),
      rationale: rationale,
      suggestedAtUtc: DateTime.now().toUtc(),
    );
    final list = _candidates.putIfAbsent(ownerId, () => []);
    list.add(candidate);
    return candidate;
  }

  @override
  Future<void> dismissSuggestedFact({
    required String ownerId,
    required String candidateId,
  }) async {
    _candidates[ownerId]?.removeWhere((c) => c.id == candidateId);
  }

  @override
  Future<MemoryFact> acceptSuggestedFact({
    required String ownerId,
    required String candidateId,
  }) async {
    final list = _candidates[ownerId] ?? [];
    final idx = list.indexWhere((c) => c.id == candidateId);
    if (idx == -1) {
      throw StateError('Suggested fact candidate not found: $candidateId');
    }
    final candidate = list.removeAt(idx);
    return addFact(
      ownerId: ownerId,
      factText: candidate.factText,
      source: MemoryFactSource.suggested,
    );
  }

  @override
  Future<List<MemoryFact>> loadEducationalPracticePresets({
    required String ownerId,
  }) async {
    final presets = [
      'В 7 «Б» классе 24 ученика',
      'Длительность одного урока составляет 40 минут',
      'Профильный предмет класса — углубленная математика',
    ];

    final created = <MemoryFact>[];
    for (final text in presets) {
      final fact = await addFact(
        ownerId: ownerId,
        factText: text,
        source: MemoryFactSource.manual,
      );
      created.add(fact);
    }
    return created;
  }
}
