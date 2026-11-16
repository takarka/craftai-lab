from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Any

from fastapi import APIRouter, Depends, File, Query, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.errors import ApiError
from app.core.security import CurrentUser, format_utc, get_current_user, utc_now
from app.modules.lab.context_assembler import SkillContextItem
from app.modules.lab.materials_models import LabSkillOverrideRevisionModel
from app.modules.lab.models import AgentModel, MaterialModel, MemoryEntryModel
from app.modules.lab.photos import (
    PhotoTextExtractor,
    VisionModelPhotoTextExtractor,
    store_and_extract_photo,
)
from app.modules.mcp import save_material_record

router = APIRouter(prefix="/lab/v1", tags=["lab-resources"])


@dataclass(frozen=True)
class CatalogSkill:
    slug: str
    title: str
    version: str
    content: str


LAB_SKILL_CATALOG: dict[str, CatalogSkill] = {
    "lesson-structure": CatalogSkill(
        slug="lesson-structure",
        title="Структура урока 45 минут",
        version="1.0.0",
        content=(
            "Разбивай план урока на этапы: актуализация (5 мин), объяснение (15 мин), "
            "практика (15 мин), рефлексия и проверка (10 мин)."
        ),
    ),
    "assessment-rubric": CatalogSkill(
        slug="assessment-rubric",
        title="Критериальное оценивание",
        version="1.0.0",
        content=(
            "К каждому заданию формируй 2–3 измеримых критерия проверки и краткий ключ ответа "
            "для быстрой проверки учителем."
        ),
    ),
}


def get_photo_extractor() -> PhotoTextExtractor:
    return VisionModelPhotoTextExtractor()


class CreateMaterialRequest(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    content: str = Field(min_length=1, max_length=10000)
    source: str = Field(default="text", pattern="^(text|photo)$")


class MemoryEntryCreateRequest(BaseModel):
    content: str = Field(min_length=1, max_length=5000)


class MemoryEntryUpdateRequest(BaseModel):
    content: str = Field(min_length=1, max_length=5000)


class SkillUpdateRequest(BaseModel):
    enabled: bool = True
    override_text: str = Field(default="", max_length=5000)
    allow_save: bool = False
    allow_search: bool = False


def detect_skill_rule_collisions(
    *,
    override_text: str,
    allow_save: bool,
    allow_search: bool,
) -> list[str]:
    lower = override_text.lower()
    collisions: list[str] = []
    if ("save_material" in lower or "сохраняй материал" in lower) and not allow_save:
        collisions.append(
            "Скилл упоминает сохранение материала, но разрешение save_material выключено — "
            "приоритет у настроек инструментов агента, инструмент вызван не будет."
        )
    if ("search_materials" in lower or "ищи в материалах" in lower) and not allow_search:
        collisions.append(
            "Скилл упоминает поиск по материалам, но разрешение search_materials выключено — "
            "поиск и автоподстановка материалов не выполнятся."
        )
    if "игнорируй правила платформы" in lower or "ignore platform" in lower:
        collisions.append(
            "Правила платформы имеют наивысший приоритет и не могут быть переопределены скиллом."
        )
    return collisions


async def load_agent_context_data(
    db: AsyncSession,
    *,
    owner_id: str,
    agent_id: str,
    allow_search: bool,
    material_query: str | None = None,
) -> tuple[list[SkillContextItem], list[str], list[str]]:
    """Loads active skills, non-deleted memory entries, and materials (only if allow_search=True)."""
    mem_rows = (
        await db.execute(
            select(MemoryEntryModel)
            .where(
                MemoryEntryModel.owner_id == owner_id,
                MemoryEntryModel.agent_id == agent_id,
                MemoryEntryModel.deleted_at.is_(None),
            )
            .order_by(MemoryEntryModel.created_at.asc())
        )
    ).scalars().all()
    memory_facts = [r.text for r in mem_rows]

    skill_rows = (
        await db.execute(
            select(LabSkillOverrideRevisionModel)
            .where(
                LabSkillOverrideRevisionModel.owner_id == owner_id,
                LabSkillOverrideRevisionModel.agent_id == agent_id,
            )
            .order_by(LabSkillOverrideRevisionModel.revision.desc())
        )
    ).scalars().all()
    latest_by_slug: dict[str, LabSkillOverrideRevisionModel] = {}
    for row in skill_rows:
        if row.skill_slug not in latest_by_slug:
            latest_by_slug[row.skill_slug] = row

    skills: list[SkillContextItem] = []
    for slug, cat in LAB_SKILL_CATALOG.items():
        rev = latest_by_slug.get(slug)
        if rev is not None and rev.enabled:
            skills.append(
                SkillContextItem(
                    slug=cat.slug,
                    title=cat.title,
                    content=cat.content,
                    override_text=rev.override_text or None,
                )
            )

    # Rule 3.2: if search is disabled, materials are NEVER injected automatically into context.
    knowledge_chunks: list[str] = []
    if allow_search:
        mat_rows = (
            await db.execute(
                select(MaterialModel)
                .where(
                    MaterialModel.owner_id == owner_id,
                    MaterialModel.agent_id == agent_id,
                )
                .order_by(MaterialModel.created_at.desc())
            )
        ).scalars().all()
        q = (material_query or "").strip().lower()
        for m in mat_rows:
            if not q or q in m.title.lower() or q in m.text.lower():
                knowledge_chunks.append(f"{m.title}: {m.text}")

    return skills, memory_facts, knowledge_chunks


@router.get("/agents/{agent_id}/materials")
async def list_materials(
    agent_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    rows = (
        await db.execute(
            select(MaterialModel)
            .where(
                MaterialModel.owner_id == current_user.user_id,
                MaterialModel.agent_id == agent_id,
            )
            .order_by(MaterialModel.created_at.desc())
        )
    ).scalars().all()
    return {
        "items": [
            {
                "id": r.id,
                "agent_id": r.agent_id,
                "title": r.title,
                "content": r.text,
                "source": r.source,
                "created_at_utc": r.created_at,
            }
            for r in rows
        ]
    }


@router.post("/agents/{agent_id}/materials", status_code=201)
async def create_material(
    agent_id: str,
    body: CreateMaterialRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    row = await save_material_record(
        db,
        owner_id=current_user.user_id,
        agent_id=agent_id,
        title=body.title,
        content=body.content,
        source=body.source,
    )
    return {
        "id": row.id,
        "agent_id": row.agent_id,
        "title": row.title,
        "content": row.text,
        "source": row.source,
        "created_at_utc": row.created_at,
    }


@router.delete("/agents/{agent_id}/materials/{material_id}", status_code=204)
async def delete_material(
    agent_id: str,
    material_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    row = (
        await db.execute(
            select(MaterialModel).where(
                MaterialModel.id == material_id,
                MaterialModel.agent_id == agent_id,
                MaterialModel.owner_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise ApiError(status_code=404, code="material.not-found", message="Материал не найден.")
    await db.delete(row)
    await db.commit()


@router.post("/agents/{agent_id}/photos", status_code=201)
async def upload_photo_for_review(
    agent_id: str,
    file: UploadFile = File(...),
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    extractor: PhotoTextExtractor = Depends(get_photo_extractor),
) -> dict[str, Any]:
    raw_bytes = await file.read()
    row = await store_and_extract_photo(
        db,
        owner_id=current_user.user_id,
        agent_id=agent_id,
        file_name=file.filename or "photo.jpg",
        raw_bytes=raw_bytes,
        extractor=extractor,
    )
    return {
        "photo_id": row.id,
        "agent_id": row.agent_id,
        "mime_type": row.mime_type,
        "size_bytes": row.size_bytes,
        "extracted_text": row.extracted_text,
        "saved_as_material": False,
        "expires_at_utc": row.expires_at_utc,
    }


@router.get("/agents/{agent_id}/memory")
async def list_memory_entries(
    agent_id: str,
    query: str | None = Query(default=None),
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    rows = (
        await db.execute(
            select(MemoryEntryModel)
            .where(
                MemoryEntryModel.owner_id == current_user.user_id,
                MemoryEntryModel.agent_id == agent_id,
                MemoryEntryModel.deleted_at.is_(None),
            )
            .order_by(MemoryEntryModel.created_at.desc())
        )
    ).scalars().all()
    q = (query or "").strip().lower()
    if q:
        rows = [r for r in rows if q in r.text.lower()]
    return {
        "items": [
            {
                "id": r.id,
                "agent_id": r.agent_id,
                "content": r.text,
                "created_at_utc": r.created_at,
            }
            for r in rows
        ]
    }


@router.post("/agents/{agent_id}/memory", status_code=201)
async def create_memory_entry(
    agent_id: str,
    body: MemoryEntryCreateRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    agent_epoch = (
        await db.execute(
            select(AgentModel.epoch).where(
                AgentModel.id == agent_id,
                AgentModel.owner_id == current_user.user_id,
                AgentModel.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()

    row = MemoryEntryModel(
        id=str(uuid.uuid4()),
        owner_id=current_user.user_id,
        agent_id=agent_id,
        epoch=int(agent_epoch or 0),
        text=body.content.strip(),
        created_at=format_utc(utc_now()),
    )
    db.add(row)
    await db.commit()
    return {
        "id": row.id,
        "agent_id": row.agent_id,
        "content": row.text,
        "created_at_utc": row.created_at,
    }


@router.patch("/agents/{agent_id}/memory/{entry_id}")
async def update_memory_entry(
    agent_id: str,
    entry_id: str,
    body: MemoryEntryUpdateRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    row = (
        await db.execute(
            select(MemoryEntryModel).where(
                MemoryEntryModel.id == entry_id,
                MemoryEntryModel.agent_id == agent_id,
                MemoryEntryModel.owner_id == current_user.user_id,
                MemoryEntryModel.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise ApiError(status_code=404, code="memory.not-found", message="Запись памяти не найдена.")
    row.text = body.content.strip()
    await db.commit()
    return {
        "id": row.id,
        "agent_id": row.agent_id,
        "content": row.text,
        "created_at_utc": row.created_at,
    }


@router.delete("/agents/{agent_id}/memory/{entry_id}", status_code=204)
async def delete_memory_entry(
    agent_id: str,
    entry_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    row = (
        await db.execute(
            select(MemoryEntryModel).where(
                MemoryEntryModel.id == entry_id,
                MemoryEntryModel.agent_id == agent_id,
                MemoryEntryModel.owner_id == current_user.user_id,
                MemoryEntryModel.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise ApiError(status_code=404, code="memory.not-found", message="Запись памяти не найдена.")
    row.deleted_at = format_utc(utc_now())
    await db.commit()


@router.get("/agents/{agent_id}/skills")
async def list_agent_skills(
    agent_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    rows = (
        await db.execute(
            select(LabSkillOverrideRevisionModel)
            .where(
                LabSkillOverrideRevisionModel.owner_id == current_user.user_id,
                LabSkillOverrideRevisionModel.agent_id == agent_id,
            )
            .order_by(LabSkillOverrideRevisionModel.revision.desc())
        )
    ).scalars().all()
    latest: dict[str, LabSkillOverrideRevisionModel] = {}
    for r in rows:
        if r.skill_slug not in latest:
            latest[r.skill_slug] = r

    items = []
    for slug, cat in LAB_SKILL_CATALOG.items():
        rev = latest.get(slug)
        items.append(
            {
                "slug": cat.slug,
                "title": cat.title,
                "version": cat.version,
                "base_content": cat.content,
                "enabled": rev.enabled if rev is not None else False,
                "override_text": rev.override_text if rev is not None else "",
                "revision": rev.revision if rev is not None else 0,
            }
        )
    return {"items": items}


@router.put("/agents/{agent_id}/skills/{slug}")
async def update_agent_skill(
    agent_id: str,
    slug: str,
    body: SkillUpdateRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    cat = LAB_SKILL_CATALOG.get(slug)
    if cat is None:
        raise ApiError(status_code=404, code="skill.not-found", message="Скилл не найден.")

    max_rev = (
        await db.execute(
            select(func.coalesce(func.max(LabSkillOverrideRevisionModel.revision), 0)).where(
                LabSkillOverrideRevisionModel.owner_id == current_user.user_id,
                LabSkillOverrideRevisionModel.agent_id == agent_id,
                LabSkillOverrideRevisionModel.skill_slug == slug,
            )
        )
    ).scalar_one()
    next_rev = int(max_rev or 0) + 1
    clean_override = body.override_text.strip()

    row = LabSkillOverrideRevisionModel(
        id=str(uuid.uuid4()),
        owner_id=current_user.user_id,
        agent_id=agent_id,
        skill_slug=slug,
        revision=next_rev,
        enabled=body.enabled,
        override_text=clean_override,
        created_at_utc=format_utc(utc_now()),
    )
    db.add(row)
    await db.commit()

    collisions = detect_skill_rule_collisions(
        override_text=clean_override,
        allow_save=body.allow_save,
        allow_search=body.allow_search,
    )
    return {
        "slug": cat.slug,
        "title": cat.title,
        "version": cat.version,
        "enabled": row.enabled,
        "override_text": row.override_text,
        "revision": row.revision,
        "collisions": collisions,
    }
