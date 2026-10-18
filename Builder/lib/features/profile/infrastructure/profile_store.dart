import 'dart:convert';

import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../../../core/storage/workspace/workspace_storage_service.dart';
import '../../onboarding/domain/assistant_setup.dart';
import '../../onboarding/domain/initial_workspace_repository.dart';
import '../domain/profile.dart';

class ProfileStore {
  ProfileStore({required this.database, required this.workspace});
  final StorageDatabase database;
  final WorkspaceStorageService workspace;

  void _check(String ownerId, int? epoch, WorkspaceWritePermit permit) {
    if (permit.ownerId != ownerId ||
        !permit.isCurrent ||
        workspace.activeOwnerId != ownerId ||
        workspace.activeEpoch != epoch) {
      throw StateError('Profile workspace changed');
    }
  }

  Future<TeacherPreferences?> readPreferences(String ownerId) async {
    await database.open();
    final rows = await database.db.query(
      StorageSchemaV1.tableTeacherPreferences,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return TeacherPreferences(
      setup: AssistantSetup(
        subject: SchoolSubject.values
            .where((s) => s.name == row['subject'])
            .firstOrNull,
        customSubject: row['custom_subject'] as String? ?? '',
        grades: (jsonDecode(row['grades_json'] as String) as List)
            .cast<int>()
            .toSet(),
        language:
            AssistantLanguage.values
                .where((l) => l.name == row['assistant_language'])
                .firstOrNull ??
            AssistantLanguage.russian,
      ),
      uiLanguage: row['ui_language'] as String,
    );
  }

  Future<void> savePreferences({
    required WorkspaceWritePermit permit,
    required AssistantSetup setup,
    required String uiLanguage,
  }) async {
    final normalized = setup.normalized();
    if (!normalized.preferencesValid ||
        !const ['ru', 'kk'].contains(uiLanguage)) {
      throw ArgumentError('Invalid profile preferences');
    }
    final ownerId = permit.ownerId;
    final epoch = workspace.activeEpoch;
    _check(ownerId, epoch, permit);
    await database.open();
    await database.transaction((txn) async {
      _check(ownerId, epoch, permit);
      // UI language and teacher preferences never modify assistant language,
      // instructions, versions, retention or notification settings.
      final count = await txn.update(
        StorageSchemaV1.tableTeacherPreferences,
        {
          'subject': normalized.subject!.name,
          'custom_subject': normalized.customSubject,
          'grades_json': jsonEncode(normalized.grades.toList()..sort()),
          'ui_language': uiLanguage,
          'updated_at_utc': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );
      if (count != 1) throw StateError('Teacher preferences not found');
      _check(ownerId, epoch, permit);
    });
  }

  Future<AccountSnapshot?> readSnapshot(String ownerId) async {
    await database.open();
    final rows = await database.db.query(
      StorageSchemaV1.tableAccountSnapshots,
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    if (rows.isEmpty) return null;
    final snapshot = AccountSnapshot.fromJson(
      (jsonDecode(rows.single['snapshot_json'] as String) as Map)
          .cast<String, dynamic>(),
    );
    if (snapshot.ownerId != ownerId) {
      throw const FormatException('Account cache owner mismatch');
    }
    return snapshot;
  }

  Future<void> saveSnapshot(
    AccountSnapshot snapshot,
    WorkspaceWritePermit permit,
  ) async {
    final epoch = workspace.activeEpoch;
    _check(snapshot.ownerId, epoch, permit);
    await database.open();
    await database.transaction((txn) async {
      _check(snapshot.ownerId, epoch, permit);
      await txn.rawInsert(
        'INSERT OR REPLACE INTO ${StorageSchemaV1.tableAccountSnapshots} '
        '(owner_id, snapshot_json) VALUES (?, ?)',
        [snapshot.ownerId, jsonEncode(snapshot.toJson())],
      );
      _check(snapshot.ownerId, epoch, permit);
    });
  }
}
