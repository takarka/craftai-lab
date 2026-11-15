from __future__ import annotations

import uuid

from sqlalchemy import JSON, CheckConstraint, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.security import format_utc, utc_now


def new_id() -> str:
    return str(uuid.uuid4())


def timestamp() -> str:
    return format_utc(utc_now())


class AgentModel(Base):
    __tablename__ = "lab_agents"
    __table_args__ = (
        UniqueConstraint("owner_id", "slot", name="uq_lab_agent_owner_slot"),
        CheckConstraint("slot IS NULL OR slot BETWEEN 1 AND 5", name="ck_lab_agent_slot"),
        CheckConstraint(
            "(deleted_at IS NULL AND slot IS NOT NULL) OR (deleted_at IS NOT NULL AND slot IS NULL)",
            name="ck_lab_agent_active_slot",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    slot: Mapped[int | None] = mapped_column(Integer, nullable=True)
    name: Mapped[str] = mapped_column(String(200))
    task_type: Mapped[str] = mapped_column(String(100), default="custom")
    subject: Mapped[str] = mapped_column(String(200), default="")
    grade: Mapped[str] = mapped_column(String(100), default="")
    epoch: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[str] = mapped_column(String(32), default=timestamp)
    updated_at: Mapped[str] = mapped_column(String(32), default=timestamp)
    deleted_at: Mapped[str | None] = mapped_column(String(32), nullable=True)


class AgentVersionModel(Base):
    __tablename__ = "lab_agent_versions"
    __table_args__ = (UniqueConstraint("agent_id", "version", name="uq_lab_agent_version"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    agent_id: Mapped[str] = mapped_column(ForeignKey("lab_agents.id"), index=True)
    version: Mapped[int] = mapped_column(Integer)
    configuration: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[str] = mapped_column(String(32), default=timestamp)


class SkillModel(Base):
    __tablename__ = "lab_skills"

    id: Mapped[str] = mapped_column(String(100), primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(Text)


class SkillVersionModel(Base):
    __tablename__ = "lab_skill_versions"
    __table_args__ = (
        UniqueConstraint("skill_id", "version", name="uq_lab_skill_version"),
        CheckConstraint("length(instruction) <= 5000", name="ck_lab_skill_instruction"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    skill_id: Mapped[str] = mapped_column(ForeignKey("lab_skills.id"), index=True)
    version: Mapped[int] = mapped_column(Integer)
    instruction: Mapped[str] = mapped_column(Text)
    editable_instruction: Mapped[str] = mapped_column(Text, default="")


class AgentSkillOverrideModel(Base):
    __tablename__ = "lab_agent_skill_overrides"
    __table_args__ = (
        UniqueConstraint("agent_version_id", "skill_id", name="uq_lab_agent_skill_override"),
        CheckConstraint("length(instruction) <= 5000", name="ck_lab_skill_override"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    agent_version_id: Mapped[str] = mapped_column(ForeignKey("lab_agent_versions.id"), index=True)
    skill_id: Mapped[str] = mapped_column(ForeignKey("lab_skills.id"))
    instruction: Mapped[str] = mapped_column(Text)


class AgentDataMixin:
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    agent_id: Mapped[str] = mapped_column(ForeignKey("lab_agents.id"), index=True)
    epoch: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[str] = mapped_column(String(32), default=timestamp)


class MaterialModel(AgentDataMixin, Base):
    __tablename__ = "lab_materials"
    __table_args__ = (
        CheckConstraint("length(text) <= 10000", name="ck_lab_material_text"),
        CheckConstraint("source IN ('text', 'photo')", name="ck_lab_material_source"),
    )

    title: Mapped[str] = mapped_column(String(200))
    text: Mapped[str] = mapped_column(Text)
    source: Mapped[str] = mapped_column(String(10), default="text")


class MemoryEntryModel(AgentDataMixin, Base):
    __tablename__ = "lab_memory_entries"

    text: Mapped[str] = mapped_column(Text)
    deleted_at: Mapped[str | None] = mapped_column(String(32), nullable=True)


class ConversationModel(AgentDataMixin, Base):
    __tablename__ = "lab_conversations"

    title: Mapped[str] = mapped_column(String(200), default="")


class MessageModel(AgentDataMixin, Base):
    __tablename__ = "lab_messages"

    conversation_id: Mapped[str] = mapped_column(ForeignKey("lab_conversations.id"), index=True)
    role: Mapped[str] = mapped_column(String(20))
    content: Mapped[str] = mapped_column(Text)


class CourseProgressModel(Base):
    __tablename__ = "lab_course_progress"

    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    course_version: Mapped[str] = mapped_column(String(100), default="0.2")
    current_lesson: Mapped[int] = mapped_column(Integer, default=1)
    completed_lessons: Mapped[list] = mapped_column(JSON, default=list)
    updated_at: Mapped[str] = mapped_column(String(32), default=timestamp)
