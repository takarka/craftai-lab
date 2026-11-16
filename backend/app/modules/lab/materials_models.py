from __future__ import annotations

from sqlalchemy import Boolean, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class LabPhotoUploadModel(Base):
    __tablename__ = "lab_photo_uploads"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    owner_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    agent_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    file_name: Mapped[str] = mapped_column(String(255), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(64), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    storage_path: Mapped[str] = mapped_column(String(500), nullable=False)
    extracted_text: Mapped[str] = mapped_column(Text, default="", nullable=False)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
    expires_at_utc: Mapped[str] = mapped_column(String(32), index=True, nullable=False)


class LabSkillOverrideRevisionModel(Base):
    __tablename__ = "lab_skill_override_revisions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    owner_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    agent_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
    skill_slug: Mapped[str] = mapped_column(String(80), index=True, nullable=False)
    revision: Mapped[int] = mapped_column(Integer, nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    override_text: Mapped[str] = mapped_column(Text, default="", nullable=False)
    created_at_utc: Mapped[str] = mapped_column(String(32), nullable=False)
