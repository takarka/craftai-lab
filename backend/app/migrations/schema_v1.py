"""Immutable SQLAlchemy Core snapshot of schema 0001. Do not import live models here."""

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    Column,
    Float,
    ForeignKey,
    Integer,
    MetaData,
    String,
    Table,
    Text,
    UniqueConstraint,
)

metadata = MetaData()

Table(
    'users',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('email', String(255), unique=True, index=True, nullable=False),
    Column('name', String(200), nullable=False),
    Column('password_hash', String(255), nullable=False),
    Column('role', String(50), nullable=False),
    Column('must_change_password', Boolean, nullable=False),
    Column('terms_revision', String(50), nullable=False),
    Column('privacy_revision', String(50), nullable=False),
    Column('language', String(10), nullable=False),
    Column('created_at_utc', String(32), nullable=False),
    Column('deleted_at_utc', String(32), nullable=True),
)

Table(
    'refresh_sessions',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('user_id', String(36), ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
    Column('token_hash', String(64), unique=True, index=True, nullable=False),
    Column('expires_at_utc', String(32), nullable=False),
    Column('revoked_at_utc', String(32), nullable=True),
    Column('created_at_utc', String(32), nullable=False),
)

Table(
    'password_reset_tokens',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('user_id', String(36), ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
    Column('token_hash', String(64), unique=True, index=True, nullable=False),
    Column('expires_at_utc', String(32), nullable=False),
    Column('consumed_at_utc', String(32), nullable=True),
)

Table(
    'idempotency_records',
    metadata,
    Column('id', Integer, nullable=False, primary_key=True, autoincrement=True),
    Column('user_id', String(36), index=True, nullable=False),
    Column('route', String(200), nullable=False),
    Column('idempotency_key', String(100), nullable=False),
    Column('request_hash', String(64), nullable=False),
    Column('status_code', Integer, nullable=False),
    Column('response_json', JSON, nullable=False),
    Column('created_at_utc', String(32), nullable=False),
    Column('expires_at_utc', String(32), nullable=False),
    UniqueConstraint('user_id', 'route', 'idempotency_key', name='uq_idem_user_route_key'),
)

Table(
    'token_usage_ledger',
    metadata,
    Column('request_id', String(64), nullable=False, primary_key=True),
    Column('user_id', String(36), ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
    Column('model_id', String(100), nullable=False),
    Column('input_tokens', Integer, nullable=False),
    Column('output_tokens', Integer, nullable=False),
    Column('total_tokens', Integer, nullable=False),
    Column('partial', Boolean, nullable=False),
    Column('created_at_utc', String(32), nullable=False),
)

Table(
    'attachments',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('user_id', String(36), ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
    Column('file_name', String(255), nullable=False),
    Column('mime_type', String(150), nullable=False),
    Column('size_bytes', Integer, nullable=False),
    Column('status', String(32), nullable=False),
    Column('reject_reason', String(100), nullable=True),
    Column('consent_revision', String(64), nullable=False),
    Column('storage_path', String(500), nullable=True),
    Column('extracted_text', Text, nullable=True),
    Column('created_at_utc', String(32), nullable=False),
    Column('expires_at_utc', String(32), nullable=False),
)

Table(
    'content_reports',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('user_id', String(36), ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
    Column('request_id', String(64), nullable=False),
    Column('reason', String(64), nullable=False),
    Column('comment', String(1000), nullable=True),
    Column('created_at_utc', String(32), nullable=False),
)

Table(
    'lab_agents',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('owner_id', ForeignKey('users.id'), nullable=False, index=True),
    Column('slot', Integer, nullable=True),
    Column('name', String(200), nullable=False),
    Column('task_type', String(100), nullable=False),
    Column('subject', String(200), nullable=False),
    Column('grade', String(100), nullable=False),
    Column('epoch', Integer, nullable=False),
    Column('created_at', String(32), nullable=False),
    Column('updated_at', String(32), nullable=False),
    Column('deleted_at', String(32), nullable=True),
    UniqueConstraint('owner_id', 'slot', name='uq_lab_agent_owner_slot'),
    CheckConstraint('slot IS NULL OR slot BETWEEN 1 AND 5', name='ck_lab_agent_slot'),
    CheckConstraint('(deleted_at IS NULL AND slot IS NOT NULL) OR (deleted_at IS NOT NULL AND slot IS NULL)', name='ck_lab_agent_active_slot'),
)

Table(
    'lab_agent_versions',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('agent_id', ForeignKey('lab_agents.id'), nullable=False, index=True),
    Column('version', Integer, nullable=False),
    Column('configuration', JSON, nullable=False),
    Column('created_at', String(32), nullable=False),
    UniqueConstraint('agent_id', 'version', name='uq_lab_agent_version'),
)

Table(
    'lab_skills',
    metadata,
    Column('id', String(100), nullable=False, primary_key=True),
    Column('name', String(200), nullable=False),
    Column('description', Text, nullable=False),
)

Table(
    'lab_skill_versions',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('skill_id', ForeignKey('lab_skills.id'), nullable=False, index=True),
    Column('version', Integer, nullable=False),
    Column('instruction', Text, nullable=False),
    Column('editable_instruction', Text, nullable=False),
    UniqueConstraint('skill_id', 'version', name='uq_lab_skill_version'),
    CheckConstraint('length(instruction) <= 5000', name='ck_lab_skill_instruction'),
)

Table(
    'lab_agent_skill_overrides',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('agent_version_id', ForeignKey('lab_agent_versions.id'), nullable=False, index=True),
    Column('skill_id', ForeignKey('lab_skills.id'), nullable=False),
    Column('instruction', Text, nullable=False),
    UniqueConstraint('agent_version_id', 'skill_id', name='uq_lab_agent_skill_override'),
    CheckConstraint('length(instruction) <= 5000', name='ck_lab_skill_override'),
)

Table(
    'lab_materials',
    metadata,
    Column('title', String(200), nullable=False),
    Column('text', Text, nullable=False),
    Column('source', String(10), nullable=False),
    Column('id', String(36), nullable=False, primary_key=True),
    Column('owner_id', ForeignKey('users.id'), nullable=False, index=True),
    Column('agent_id', ForeignKey('lab_agents.id'), nullable=False, index=True),
    Column('epoch', Integer, nullable=False),
    Column('created_at', String(32), nullable=False),
    CheckConstraint('length(text) <= 10000', name='ck_lab_material_text'),
    CheckConstraint("source IN ('text', 'photo')", name='ck_lab_material_source'),
)

Table(
    'lab_memory_entries',
    metadata,
    Column('text', Text, nullable=False),
    Column('deleted_at', String(32), nullable=True),
    Column('id', String(36), nullable=False, primary_key=True),
    Column('owner_id', ForeignKey('users.id'), nullable=False, index=True),
    Column('agent_id', ForeignKey('lab_agents.id'), nullable=False, index=True),
    Column('epoch', Integer, nullable=False),
    Column('created_at', String(32), nullable=False),
)

Table(
    'lab_conversations',
    metadata,
    Column('title', String(200), nullable=False),
    Column('id', String(36), nullable=False, primary_key=True),
    Column('owner_id', ForeignKey('users.id'), nullable=False, index=True),
    Column('agent_id', ForeignKey('lab_agents.id'), nullable=False, index=True),
    Column('epoch', Integer, nullable=False),
    Column('created_at', String(32), nullable=False),
)

Table(
    'lab_messages',
    metadata,
    Column('conversation_id', ForeignKey('lab_conversations.id'), nullable=False, index=True),
    Column('role', String(20), nullable=False),
    Column('content', Text, nullable=False),
    Column('id', String(36), nullable=False, primary_key=True),
    Column('owner_id', ForeignKey('users.id'), nullable=False, index=True),
    Column('agent_id', ForeignKey('lab_agents.id'), nullable=False, index=True),
    Column('epoch', Integer, nullable=False),
    Column('created_at', String(32), nullable=False),
)

Table(
    'lab_course_progress',
    metadata,
    Column('owner_id', ForeignKey('users.id'), nullable=False, primary_key=True),
    Column('course_version', String(100), nullable=False),
    Column('current_lesson', Integer, nullable=False),
    Column('completed_lessons', JSON, nullable=False),
    Column('updated_at', String(32), nullable=False),
)

Table(
    'lab_photo_uploads',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('owner_id', String(36), index=True, nullable=False),
    Column('agent_id', String(36), index=True, nullable=False),
    Column('file_name', String(255), nullable=False),
    Column('mime_type', String(64), nullable=False),
    Column('size_bytes', Integer, nullable=False),
    Column('storage_path', String(500), nullable=False),
    Column('extracted_text', Text, nullable=False),
    Column('created_at_utc', String(32), nullable=False),
    Column('expires_at_utc', String(32), index=True, nullable=False),
)

Table(
    'lab_skill_override_revisions',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('owner_id', String(36), index=True, nullable=False),
    Column('agent_id', String(36), index=True, nullable=False),
    Column('skill_slug', String(80), index=True, nullable=False),
    Column('revision', Integer, nullable=False),
    Column('enabled', Boolean, nullable=False),
    Column('override_text', Text, nullable=False),
    Column('created_at_utc', String(32), nullable=False),
)

Table(
    'lab_runs',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('owner_id', String(36), index=True, nullable=False),
    Column('agent_id', String(36), index=True, nullable=False),
    Column('agent_version_id', String(36), nullable=False),
    Column('conversation_id', String(36), index=True, nullable=True),
    Column('epoch', Integer, nullable=False),
    Column('model_id', String(120), nullable=False),
    Column('version_snapshot_json', JSON, nullable=False),
    Column('status', String(32), index=True, nullable=False),
    Column('stop_reason', String(64), nullable=True),
    Column('idempotency_key', String(100), index=True, nullable=True),
    Column('user_prompt', Text, nullable=False),
    Column('final_output', Text, nullable=True),
    Column('error_code', String(80), nullable=True),
    Column('error_message', Text, nullable=True),
    Column('tool_calls_count', Integer, nullable=False),
    Column('active_elapsed_ms', Integer, nullable=False),
    Column('created_at_utc', String(32), nullable=False),
    Column('updated_at_utc', String(32), nullable=False),
    Column('completed_at_utc', String(32), nullable=True),
)

Table(
    'lab_run_events',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('run_id', String(36), ForeignKey('lab_runs.id', ondelete='CASCADE'), index=True, nullable=False),
    Column('owner_id', String(36), index=True, nullable=False),
    Column('agent_id', String(36), index=True, nullable=False),
    Column('epoch', Integer, nullable=False),
    Column('sequence', Integer, nullable=False),
    Column('event_type', String(64), nullable=False),
    Column('payload_json', JSON, nullable=False),
    Column('created_at_utc', String(32), nullable=False),
)

Table(
    'lab_pending_actions',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('run_id', String(36), ForeignKey('lab_runs.id', ondelete='CASCADE'), index=True, nullable=False),
    Column('owner_id', String(36), index=True, nullable=False),
    Column('agent_id', String(36), index=True, nullable=False),
    Column('tool_call_id', String(100), nullable=False),
    Column('tool_name', String(80), nullable=False),
    Column('params_json', JSON, nullable=False),
    Column('params_hash', String(64), nullable=False),
    Column('status', String(32), index=True, nullable=False),
    Column('created_at_utc', String(32), nullable=False),
    Column('expires_at_utc', String(32), nullable=False),
    Column('resolved_at_utc', String(32), nullable=True),
)

Table(
    'lab_usage_ledger',
    metadata,
    Column('id', String(36), nullable=False, primary_key=True),
    Column('run_id', String(36), ForeignKey('lab_runs.id', ondelete='CASCADE'), index=True, nullable=False),
    Column('owner_id', String(36), index=True, nullable=False),
    Column('model_id', String(120), nullable=False),
    Column('input_tokens', Integer, nullable=False),
    Column('output_tokens', Integer, nullable=False),
    Column('total_tokens', Integer, nullable=False),
    Column('estimated_cost_usd', Float, nullable=False),
    Column('partial', Boolean, nullable=False),
    Column('created_at_utc', String(32), nullable=False),
)
