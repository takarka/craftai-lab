import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/storage/database/storage_database.dart';
import '../../../core/storage/schema/storage_schema_v1.dart';
import '../domain/assistant_setup.dart';
import '../domain/initial_workspace_repository.dart';

class PermitRevokedException implements Exception {
  const PermitRevokedException([this.message = 'Workspace write permit was revoked before commit.']);
  final String message;

  @override
  String toString() => 'PermitRevokedException: $message';
}

final class PersistentInitialWorkspaceRepository implements InitialWorkspaceRepository {
  PersistentInitialWorkspaceRepository({
    required this.database,
    required this.installationId,
  });

  final StorageDatabase database;
  final String installationId;

  @override
  bool get isAvailable => true;

  @override
  Future<InitialWorkspace> createIfAbsent({
    required WorkspaceWritePermit permit,
    required AssistantSetup setup,
  }) async {
    if (!permit.isCurrent) {
      throw const PermitRevokedException();
    }

    if (!database.isOpen) {
      await database.open();
    }

    return await database.transaction<InitialWorkspace>((txn) async {
      // 1. Recheck permit inside transaction before any writes
      if (!permit.isCurrent) {
        throw const PermitRevokedException();
      }

      final ownerId = permit.ownerId;

      // 2. Check if workspace already exists for this owner (idempotency)
      final existingRows = await txn.query(
        StorageSchemaV1.tableWorkspaces,
        where: 'owner_id = ?',
        whereArgs: [ownerId],
      );

      if (existingRows.isNotEmpty) {
        // Read existing setup to return without overwriting
        final prefRows = await txn.query(
          StorageSchemaV1.tableTeacherPreferences,
          where: 'owner_id = ?',
          whereArgs: [ownerId],
        );
        final configRows = await txn.query(
          StorageSchemaV1.tableAssistantConfigurations,
          where: 'owner_id = ?',
          whereArgs: [ownerId],
        );

        if (prefRows.isNotEmpty && configRows.isNotEmpty) {
          final pref = prefRows.first;
          final config = configRows.first;

          final subjectName = pref['subject'] as String?;
          final schoolSubject = SchoolSubject.values.firstWhere(
            (s) => s.name == subjectName,
            orElse: () => SchoolSubject.other,
          );

          final gradesRaw = jsonDecode(pref['grades_json'] as String? ?? '[]') as List<dynamic>;
          final grades = gradesRaw.map((e) => e as int).toSet();

          final langName = pref['assistant_language'] as String?;
          final lang = AssistantLanguage.values.firstWhere(
            (l) => l.name == langName,
            orElse: () => AssistantLanguage.russian,
          );

          final existingSetup = AssistantSetup(
            subject: schoolSubject,
            customSubject: pref['custom_subject'] as String? ?? '',
            grades: grades,
            language: lang,
            name: config['name'] as String? ?? '',
          );

          return InitialWorkspace(ownerId: ownerId, setup: existingSetup);
        }
      }

      // 3. New workspace creation
      final normalized = setup.normalized();
      final nowUtc = DateTime.now().toUtc().toIso8601String();

      await txn.insert(
        StorageSchemaV1.tableWorkspaces,
        {
          'owner_id': ownerId,
          'installation_id': installationId,
          'schema_version': StorageSchemaV1.version,
          'workspace_epoch': 1,
          'created_at_utc': nowUtc,
          'updated_at_utc': nowUtc,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await txn.insert(
        StorageSchemaV1.tableTeacherPreferences,
        {
          'owner_id': ownerId,
          'subject': normalized.subject?.name ?? SchoolSubject.other.name,
          'custom_subject': normalized.customSubject,
          'grades_json': jsonEncode(normalized.grades.toList()..sort()),
          'ui_language': 'ru',
          'assistant_language': normalized.language.name,
          'reminders_enabled': 0,
          'storage_retention_days': null,
          'updated_at_utc': nowUtc,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await txn.insert(
        StorageSchemaV1.tableAssistantConfigurations,
        {
          'owner_id': ownerId,
          'name': normalized.name,
          'selected_category': null,
          'enabled_skills_json': '[]',
          'system_rules_json': '[]',
          'state_revision': 1,
          'updated_at_utc': nowUtc,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      // 4. Final check before commit: permit must still be valid
      if (!permit.isCurrent) {
        throw const PermitRevokedException();
      }

      return InitialWorkspace(ownerId: ownerId, setup: normalized);
    });
  }
}
