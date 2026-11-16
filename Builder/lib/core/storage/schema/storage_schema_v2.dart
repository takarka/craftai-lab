import 'package:sqflite/sqflite.dart';

abstract final class StorageSchemaV2 {
  static const version = 2;
  static const agentTables = [
    'assistant_configurations',
    'instruction_rules',
    'assistant_versions',
    'conversations',
    'messages',
    'request_traces',
    'knowledge_documents',
    'document_revisions',
    'knowledge_chunks',
    'memory_facts',
    'tool_grants',
    'pending_actions',
    'tool_invocations',
    'file_staging_journal',
    'skill_scenarios',
  ];

  static Future<void> ensure(DatabaseExecutor db) async {
    for (final table in agentTables) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (columns.isNotEmpty &&
          !columns.any((column) => column['name'] == 'agent_id')) {
        // Legacy rows stay unassigned; never expose them as a server agent's data.
        await db.execute('ALTER TABLE $table ADD COLUMN agent_id TEXT');
      }
    }
    await db.execute('''CREATE TABLE IF NOT EXISTS lab_agents_cache (
      owner_id TEXT NOT NULL, agent_id TEXT NOT NULL, snapshot TEXT NOT NULL,
      PRIMARY KEY(owner_id, agent_id))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS lab_agent_selection (
      owner_id TEXT PRIMARY KEY, agent_id TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS lab_agent_drafts (
      owner_id TEXT NOT NULL, agent_id TEXT NOT NULL, epoch INTEGER NOT NULL,
      payload TEXT NOT NULL, PRIMARY KEY(owner_id, agent_id))''');
  }
}
