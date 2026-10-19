abstract final class StorageSchemaV1 {
  static const int version = 1;

  // Table names
  static const String tableWorkspaces = 'workspaces';
  static const String tableTeacherPreferences = 'teacher_preferences';
  static const String tableAssistantConfigurations = 'assistant_configurations';
  static const String tableInstructionRules = 'instruction_rules';
  static const String tableAssistantVersions = 'assistant_versions';
  static const String tableConversations = 'conversations';
  static const String tableMessages = 'messages';
  static const String tableRequestTraces = 'request_traces';
  static const String tableKnowledgeDocuments = 'knowledge_documents';
  static const String tableDocumentRevisions = 'document_revisions';
  static const String tableKnowledgeChunks = 'knowledge_chunks';
  static const String tableMemoryFacts = 'memory_facts';
  static const String tableToolGrants = 'tool_grants';
  static const String tablePendingActions = 'pending_actions';
  static const String tableToolInvocations = 'tool_invocations';
  static const String tableCourseProgress = 'course_progress';
  static const String tableQuizAttempts = 'quiz_attempts';
  static const String tableFileStagingJournal = 'file_staging_journal';
  static const String tablePolicyAcknowledgments = 'policy_acknowledgments';

  static const String tableAccountSnapshots = 'account_snapshots';
  static const String tableSkillScenarios = 'skill_scenarios';
  static const String tableCalendarEvents = 'calendar_events';
  static const String tableCalendarOverrides = 'calendar_overrides';
  static const String tableCalendarSync = 'calendar_sync_state';
  static const String tableCalendarPending = 'calendar_pending_creates';

  static const List<String> createStatements = [
    // Additive calendar cache (EF-02); onOpen upgrades existing installations.
    '''
    CREATE TABLE IF NOT EXISTS $tableCalendarEvents (
      owner_id TEXT NOT NULL,
      id TEXT NOT NULL,
      version INTEGER NOT NULL,
      event_json TEXT NOT NULL,
      PRIMARY KEY (owner_id, id),
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tableCalendarOverrides (
      owner_id TEXT NOT NULL,
      event_id TEXT NOT NULL,
      occurrence_date TEXT NOT NULL,
      canceled INTEGER NOT NULL,
      title TEXT,
      notes TEXT,
      start_local TEXT,
      end_local TEXT,
      PRIMARY KEY (owner_id, event_id, occurrence_date),
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tableCalendarSync (
      owner_id TEXT PRIMARY KEY,
      cursor TEXT NOT NULL,
      synced_at_utc TEXT NOT NULL,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tableCalendarPending (
      owner_id TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      input_json TEXT NOT NULL,
      created_at_utc TEXT NOT NULL,
      PRIMARY KEY (owner_id, idempotency_key),
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',
    // Additive, idempotent upgrade for existing v1 workspaces on open.
    '''
    CREATE TABLE IF NOT EXISTS $tableSkillScenarios (
      owner_id TEXT NOT NULL,
      id TEXT NOT NULL,
      scenario_json TEXT NOT NULL,
      PRIMARY KEY (owner_id, id),
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',
    // Additive table; onOpen also upgrades existing v1 installations.
    '''
    CREATE TABLE IF NOT EXISTS $tableAccountSnapshots (
      owner_id TEXT PRIMARY KEY,
      snapshot_json TEXT NOT NULL,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',
    // 1. Workspaces
    '''
    CREATE TABLE IF NOT EXISTS $tableWorkspaces (
      owner_id TEXT PRIMARY KEY,
      installation_id TEXT NOT NULL,
      schema_version INTEGER NOT NULL,
      workspace_epoch INTEGER NOT NULL,
      created_at_utc TEXT NOT NULL,
      updated_at_utc TEXT NOT NULL
    );
    ''',

    // 2. Teacher Preferences
    '''
    CREATE TABLE IF NOT EXISTS $tableTeacherPreferences (
      owner_id TEXT PRIMARY KEY,
      subject TEXT NOT NULL,
      custom_subject TEXT,
      grades_json TEXT NOT NULL,
      ui_language TEXT NOT NULL,
      assistant_language TEXT NOT NULL,
      reminders_enabled INTEGER NOT NULL DEFAULT 0,
      storage_retention_days INTEGER,
      updated_at_utc TEXT NOT NULL,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 3. Assistant Configurations
    '''
    CREATE TABLE IF NOT EXISTS $tableAssistantConfigurations (
      owner_id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      selected_category TEXT,
      enabled_skills_json TEXT NOT NULL,
      system_rules_json TEXT NOT NULL,
      state_revision INTEGER NOT NULL DEFAULT 1,
      updated_at_utc TEXT NOT NULL,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 4. Instruction Rules
    '''
    CREATE TABLE IF NOT EXISTS $tableInstructionRules (
      id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      group_name TEXT NOT NULL,
      rule_text TEXT NOT NULL,
      is_enabled INTEGER NOT NULL,
      sort_order INTEGER NOT NULL,
      source TEXT NOT NULL,
      revision INTEGER NOT NULL,
      updated_at_utc TEXT NOT NULL,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 5. Assistant Versions
    '''
    CREATE TABLE IF NOT EXISTS $tableAssistantVersions (
      owner_id TEXT NOT NULL,
      version_number INTEGER NOT NULL,
      created_at_utc TEXT NOT NULL,
      reason TEXT NOT NULL,
      parent_id TEXT,
      schema_version INTEGER NOT NULL,
      snapshot_json TEXT NOT NULL,
      PRIMARY KEY(owner_id, version_number),
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 6. Conversations
    '''
    CREATE TABLE IF NOT EXISTS $tableConversations (
      id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      title TEXT NOT NULL,
      created_at_utc TEXT NOT NULL,
      activity_at_utc TEXT NOT NULL,
      retention_policy TEXT NOT NULL,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 7. Messages
    '''
    CREATE TABLE IF NOT EXISTS $tableMessages (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL,
      owner_id TEXT NOT NULL,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      status TEXT NOT NULL,
      request_id TEXT,
      assistant_version INTEGER,
      created_at_utc TEXT NOT NULL,
      FOREIGN KEY (conversation_id) REFERENCES $tableConversations(id) ON DELETE CASCADE,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 8. Request Traces
    '''
    CREATE TABLE IF NOT EXISTS $tableRequestTraces (
      request_id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      context_layers_json TEXT NOT NULL,
      sent_chunks_json TEXT NOT NULL,
      usage_json TEXT NOT NULL,
      duration_ms INTEGER NOT NULL,
      error_code TEXT,
      created_at_utc TEXT NOT NULL,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 9. Knowledge Documents
    '''
    CREATE TABLE IF NOT EXISTS $tableKnowledgeDocuments (
      id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      content_hash TEXT NOT NULL,
      file_name TEXT NOT NULL,
      file_format TEXT NOT NULL,
      file_size_bytes INTEGER NOT NULL,
      is_enabled INTEGER NOT NULL,
      index_status TEXT NOT NULL,
      created_at_utc TEXT NOT NULL,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 10. Document Revisions
    '''
    CREATE TABLE IF NOT EXISTS $tableDocumentRevisions (
      id TEXT PRIMARY KEY,
      document_id TEXT NOT NULL,
      owner_id TEXT NOT NULL,
      parser_version TEXT NOT NULL,
      embedding_model_id TEXT,
      text_content TEXT NOT NULL,
      blob_path TEXT,
      created_at_utc TEXT NOT NULL,
      FOREIGN KEY (document_id) REFERENCES $tableKnowledgeDocuments(id) ON DELETE CASCADE,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 11. Knowledge Chunks
    '''
    CREATE TABLE IF NOT EXISTS $tableKnowledgeChunks (
      id TEXT PRIMARY KEY,
      revision_id TEXT NOT NULL,
      owner_id TEXT NOT NULL,
      chunk_index INTEGER NOT NULL,
      chunk_text TEXT NOT NULL,
      page_number INTEGER,
      byte_offset INTEGER,
      embedding_metadata_json TEXT,
      FOREIGN KEY (revision_id) REFERENCES $tableDocumentRevisions(id) ON DELETE CASCADE,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 12. Memory Facts
    '''
    CREATE TABLE IF NOT EXISTS $tableMemoryFacts (
      id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      fact_text TEXT NOT NULL,
      source TEXT NOT NULL,
      is_enabled INTEGER NOT NULL,
      created_at_utc TEXT NOT NULL,
      updated_at_utc TEXT NOT NULL,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 13. Tool Grants
    '''
    CREATE TABLE IF NOT EXISTS $tableToolGrants (
      owner_id TEXT NOT NULL,
      tool_name TEXT NOT NULL,
      is_enabled INTEGER NOT NULL,
      permission_scope TEXT NOT NULL,
      revision INTEGER NOT NULL,
      updated_at_utc TEXT NOT NULL,
      PRIMARY KEY (owner_id, tool_name),
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 14. Pending Actions
    '''
    CREATE TABLE IF NOT EXISTS $tablePendingActions (
      invocation_id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      workspace_epoch INTEGER NOT NULL,
      action_name TEXT NOT NULL,
      params_hash TEXT NOT NULL,
      params_json TEXT NOT NULL,
      status TEXT NOT NULL,
      expires_at_utc TEXT,
      created_at_utc TEXT NOT NULL,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 15. Tool Invocations
    '''
    CREATE TABLE IF NOT EXISTS $tableToolInvocations (
      id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      tool_name TEXT NOT NULL,
      invocation_source TEXT NOT NULL,
      args_json TEXT NOT NULL,
      result_json TEXT,
      started_at_utc TEXT NOT NULL,
      completed_at_utc TEXT,
      execution_id TEXT,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 16. Course Progress
    '''
    CREATE TABLE IF NOT EXISTS $tableCourseProgress (
      owner_id TEXT NOT NULL,
      level_id TEXT NOT NULL,
      content_version TEXT NOT NULL,
      current_step INTEGER NOT NULL,
      completed_checkpoints_json TEXT NOT NULL,
      attempts_count INTEGER NOT NULL,
      is_completed INTEGER NOT NULL,
      updated_at_utc TEXT NOT NULL,
      PRIMARY KEY (owner_id, level_id),
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 17. Quiz Attempts
    '''
    CREATE TABLE IF NOT EXISTS $tableQuizAttempts (
      id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      level_id TEXT NOT NULL,
      question_revisions_json TEXT NOT NULL,
      answers_json TEXT NOT NULL,
      score REAL NOT NULL,
      threshold REAL NOT NULL,
      completed_at_utc TEXT NOT NULL,
      FOREIGN KEY (owner_id) REFERENCES $tableWorkspaces(owner_id) ON DELETE CASCADE
    );
    ''',

    // 18. File Staging Journal
    '''
    CREATE TABLE IF NOT EXISTS $tableFileStagingJournal (
      id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      staging_path TEXT NOT NULL,
      target_path TEXT NOT NULL,
      status TEXT NOT NULL,
      created_at_utc TEXT NOT NULL
    );
    ''',

    // 19. Policy Acknowledgments (D02 Cross-border data, etc.)
    '''
    CREATE TABLE IF NOT EXISTS $tablePolicyAcknowledgments (
      owner_id TEXT NOT NULL,
      policy_id TEXT NOT NULL,
      policy_version TEXT NOT NULL,
      acknowledged_at_utc TEXT NOT NULL,
      PRIMARY KEY (owner_id, policy_id)
    );
    ''',

    // Performance & isolation indexes
    'CREATE INDEX IF NOT EXISTS idx_messages_conv ON $tableMessages(conversation_id, created_at_utc);',
    'CREATE INDEX IF NOT EXISTS idx_traces_owner ON $tableRequestTraces(owner_id, created_at_utc);',
    'CREATE INDEX IF NOT EXISTS idx_docs_owner ON $tableKnowledgeDocuments(owner_id);',
    'CREATE INDEX IF NOT EXISTS idx_chunks_rev ON $tableKnowledgeChunks(revision_id);',
    'CREATE INDEX IF NOT EXISTS idx_facts_owner ON $tableMemoryFacts(owner_id, is_enabled);',
    'CREATE INDEX IF NOT EXISTS idx_calendar_events_owner ON $tableCalendarEvents(owner_id);',
    'CREATE INDEX IF NOT EXISTS idx_calendar_overrides_owner ON $tableCalendarOverrides(owner_id, event_id);',
    'CREATE INDEX IF NOT EXISTS idx_staging_status ON $tableFileStagingJournal(status);',
  ];
}
