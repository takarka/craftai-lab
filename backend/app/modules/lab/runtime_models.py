from __future__ import annotations

from sqlalchemy import Boolean, Float, ForeignKey, Integer, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class LabRunModel(Base):
    __tablename__ = "lab_runs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    owner_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    agent_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    agent_version_id: Mapped[str] = mapped_column(String(36), nullable=False)
    conversation_id: Mapped[str | None] = mapped_column(String(36), index=True, nullable=True)
    epoch: Mapped[int] = mapped_column(Integer, default=1, nullable=False)

    # Snapshot of version configuration at run start
    model_id: Mapped[str] = mapped_column(String(120), nullable=False)
    version_snapshot_json: Mapped[dict] = mapped_column(JSON, nullable=False)

    # Status: queued | running | awaiting_confirmation | completed | failed | cancelled
    status: Mapped[str] = mapped_column(String(32), default="running", index=True, nullable=False)
    stop_reason: Mapped[str | None] = mapped_column(String(64), nullable=True)
    idempotency_key: Mapped[str | None] = mapped_column(String(100), index=True, nullable=True)

    user_prompt: Mapped[str] = mapped_column(Text, nullable=False)
    final_output: Mapped[str | None] = mapped_column(Text, nullable=True)
    error_code: Mapped[str | None] = mapped_column(String(80), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)

    tool_calls_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    active_elapsed_ms: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    updated_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    completed_at_utc: Mapped[str | None] = mapped_column(String(32), nullable=True)


class LabRunEventModel(Base):
    __tablename__ = "lab_run_events"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    run_id: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("lab_runs.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    owner_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    agent_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    epoch: Mapped[int] = mapped_column(Integer, nullable=False)
    sequence: Mapped[int] = mapped_column(Integer, nullable=False)
    event_type: Mapped[str] = mapped_column(String(64), nullable=False)
    payload_json: Mapped[dict] = mapped_column(JSON, nullable=False)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)


class LabPendingActionModel(Base):
    __tablename__ = "lab_pending_actions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    run_id: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("lab_runs.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    owner_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    agent_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    tool_call_id: Mapped[str] = mapped_column(String(100), nullable=False)
    tool_name: Mapped[str] = mapped_column(String(80), nullable=False)
    params_json: Mapped[dict] = mapped_column(JSON, nullable=False)
    params_hash: Mapped[str] = mapped_column(String(64), nullable=False)

    # Status: pending | approved | denied | expired | cancelled
    status: Mapped[str] = mapped_column(String(32), default="pending", index=True, nullable=False)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    expires_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    resolved_at_utc: Mapped[str | None] = mapped_column(String(32), nullable=True)


class LabUsageLedgerModel(Base):
    __tablename__ = "lab_usage_ledger"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    run_id: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("lab_runs.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    owner_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    model_id: Mapped[str] = mapped_column(String(120), nullable=False)
    input_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    total_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    estimated_cost_usd: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    partial: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
