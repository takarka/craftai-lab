import os
from collections.abc import AsyncGenerator
from pathlib import Path

from sqlalchemy import JSON, Boolean, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.core.config import settings

# Ensure local SQLite data directory exists when using sqlite
if settings.database_url.startswith("sqlite"):
    db_file = settings.database_url.split("///")[-1]
    if db_file and db_file != ":memory:":
        Path(db_file).parent.mkdir(parents=True, exist_ok=True)

os.makedirs(settings.storage_dir, exist_ok=True)

engine = create_async_engine(
    settings.database_url,
    echo=False,
    future=True,
)

SessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


class Base(DeclarativeBase):
    pass


class UserModel(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[str] = mapped_column(String(50), default="Teacher", nullable=False)
    must_change_password: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    terms_revision: Mapped[str] = mapped_column(String(50), nullable=False)
    privacy_revision: Mapped[str] = mapped_column(String(50), nullable=False)
    language: Mapped[str] = mapped_column(String(10), default="ru", nullable=False)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    deleted_at_utc: Mapped[str | None] = mapped_column(String(32), nullable=True)


class RefreshSessionModel(Base):
    __tablename__ = "refresh_sessions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    expires_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    revoked_at_utc: Mapped[str | None] = mapped_column(String(32), nullable=True)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)


class PasswordResetTokenModel(Base):
    __tablename__ = "password_reset_tokens"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    expires_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    consumed_at_utc: Mapped[str | None] = mapped_column(String(32), nullable=True)


class IdempotencyRecordModel(Base):
    __tablename__ = "idempotency_records"
    __table_args__ = (UniqueConstraint("user_id", "route", "idempotency_key", name="uq_idem_user_route_key"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    route: Mapped[str] = mapped_column(String(200), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(100), nullable=False)
    request_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    status_code: Mapped[int] = mapped_column(Integer, nullable=False)
    response_json: Mapped[dict] = mapped_column(JSON, nullable=False)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    expires_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)


class TokenUsageLedgerModel(Base):
    __tablename__ = "token_usage_ledger"

    request_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    model_id: Mapped[str] = mapped_column(String(100), nullable=False)
    input_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    total_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    partial: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)


class AttachmentModel(Base):
    __tablename__ = "attachments"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    file_name: Mapped[str] = mapped_column(String(255), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(150), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False)  # uploaded | rejected
    reject_reason: Mapped[str | None] = mapped_column(String(100), nullable=True)
    consent_revision: Mapped[str] = mapped_column(String(64), nullable=False)
    storage_path: Mapped[str | None] = mapped_column(String(500), nullable=True)
    extracted_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    expires_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)


class DocumentJobModel(Base):
    __tablename__ = "document_jobs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    attachment_id: Mapped[str] = mapped_column(String(36), ForeignKey("attachments.id", ondelete="CASCADE"), index=True)
    skill: Mapped[str] = mapped_column(String(32), nullable=False)  # quiz | lesson-plan
    parameters_json: Mapped[dict] = mapped_column(JSON, nullable=False)
    outputs_json: Mapped[list] = mapped_column(JSON, nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False)  # queued..succeeded|failed|canceled|expired
    progress: Mapped[int | None] = mapped_column(Integer, nullable=True)
    error_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    updated_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    expires_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)


class ArtifactModel(Base):
    __tablename__ = "artifacts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    job_id: Mapped[str] = mapped_column(String(36), ForeignKey("document_jobs.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    format: Mapped[str] = mapped_column(String(16), nullable=False)  # docx | pdf
    file_name: Mapped[str] = mapped_column(String(255), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(150), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    storage_path: Mapped[str] = mapped_column(String(500), nullable=False)
    expires_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)


class CalendarEventModel(Base):
    __tablename__ = "calendar_events"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    notes: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    all_day: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    start_local: Mapped[str] = mapped_column(String(32), nullable=False)
    end_local: Mapped[str] = mapped_column(String(32), nullable=False)
    time_zone: Mapped[str | None] = mapped_column(String(64), nullable=True)
    recurrence_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    reminders_json: Mapped[list] = mapped_column(JSON, default=list, nullable=False)
    subject: Mapped[str | None] = mapped_column(String(100), nullable=True)
    grade: Mapped[int | None] = mapped_column(Integer, nullable=True)
    version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    updated_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)


class CalendarOccurrenceOverrideModel(Base):
    __tablename__ = "calendar_occurrence_overrides"
    __table_args__ = (UniqueConstraint("event_id", "occurrence_date", name="uq_event_occurrence_date"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    event_id: Mapped[str] = mapped_column(String(36), ForeignKey("calendar_events.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    occurrence_date: Mapped[str] = mapped_column(String(10), nullable=False)
    canceled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    notes: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    start_local: Mapped[str | None] = mapped_column(String(32), nullable=True)
    end_local: Mapped[str | None] = mapped_column(String(32), nullable=True)


class CalendarChangeLogModel(Base):
    __tablename__ = "calendar_change_log"

    seq: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    event_id: Mapped[str] = mapped_column(String(36), nullable=False)
    change_type: Mapped[str] = mapped_column(String(16), nullable=False)  # upsert | delete
    changed_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)


class ScheduleModel(Base):
    __tablename__ = "schedules"
    __table_args__ = (UniqueConstraint("user_id", "template", name="uq_schedule_user_template"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    template: Mapped[str] = mapped_column(String(32), nullable=False)  # daily-brief | idea-generator
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    time_zone: Mapped[str] = mapped_column(String(64), default="Asia/Almaty", nullable=False)
    timing_json: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    parameters_json: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    extra_context: Mapped[str | None] = mapped_column(Text, nullable=True)
    consent_revision: Mapped[str] = mapped_column(String(64), default="schedules-2026-10-v1", nullable=False)
    next_run_at_utc: Mapped[str | None] = mapped_column(String(32), nullable=True)
    version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    updated_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)


class ScheduleRunModel(Base):
    __tablename__ = "schedule_runs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    schedule_id: Mapped[str] = mapped_column(String(36), ForeignKey("schedules.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    trigger: Mapped[str] = mapped_column(String(16), nullable=False)  # scheduled | manual
    scheduled_for_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(24), nullable=False)  # queued|running|succeeded|failed|skipped|canceled
    status_reason: Mapped[str | None] = mapped_column(String(64), nullable=True)
    delivery: Mapped[str] = mapped_column(String(24), default="pending", nullable=False)
    result_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    finished_at_utc: Mapped[str | None] = mapped_column(String(32), nullable=True)


class UserDeviceModel(Base):
    __tablename__ = "user_devices"
    __table_args__ = (UniqueConstraint("user_id", "installation_id", name="uq_user_device_inst"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    installation_id: Mapped[str] = mapped_column(String(64), nullable=False)
    platform: Mapped[str] = mapped_column(String(16), nullable=False)  # android | ios
    push_token: Mapped[str] = mapped_column(String(512), nullable=False)
    locale: Mapped[str] = mapped_column(String(16), default="ru", nullable=False)
    app_version: Mapped[str] = mapped_column(String(64), default="0.1.0", nullable=False)
    updated_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)


class ContentReportModel(Base):
    __tablename__ = "content_reports"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    request_id: Mapped[str] = mapped_column(String(64), nullable=False)
    reason: Mapped[str] = mapped_column(String(64), nullable=False)
    comment: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        yield session
