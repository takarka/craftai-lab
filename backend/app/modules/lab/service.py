from copy import deepcopy

from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import UserModel
from app.core.errors import ApiError
from app.modules.lab.catalog import model_catalog
from app.modules.lab.models import (
    AgentModel,
    AgentSkillOverrideModel,
    AgentVersionModel,
    ConversationModel,
    MaterialModel,
    MemoryEntryModel,
    MessageModel,
    SkillVersionModel,
    timestamp,
)
from app.modules.lab.runtime_models import LabPendingActionModel, LabRunModel
from app.modules.lab.schemas import AgentCreate


async def lock_owner(db: AsyncSession, owner_id: str) -> None:
    """Acquire a DB write lock before any reads in a mutation transaction.

    UPDATE serializes writers on both PostgreSQL and SQLite; unlike an asyncio
    lock this also works across API workers. Runtime writers must reuse it and
    recheck the agent epoch before persisting side effects (LM02).
    """
    result = await db.execute(
        update(UserModel)
        .where(
            UserModel.id == owner_id,
            UserModel.deleted_at_utc.is_(None),
        )
        .values(id=UserModel.id)
    )
    if result.rowcount != 1:
        raise ApiError(401, "auth.unauthorized", "Пользователь недоступен.")


async def owned_agent(db: AsyncSession, owner_id: str, agent_id: str, *, deleted: bool = False) -> AgentModel:
    query = select(AgentModel).where(AgentModel.id == agent_id, AgentModel.owner_id == owner_id)
    if not deleted:
        query = query.where(AgentModel.deleted_at.is_(None))
    agent = await db.scalar(query)
    if agent is None:
        raise ApiError(404, "agents.not-found", "Агент не найден.")
    return agent


async def latest_version(db: AsyncSession, agent_id: str) -> AgentVersionModel:
    result = await db.scalar(
        select(AgentVersionModel)
        .where(
            AgentVersionModel.agent_id == agent_id,
        )
        .order_by(AgentVersionModel.version.desc())
        .limit(1)
    )
    if result is None:
        raise RuntimeError("Active agent has no configuration version")
    return result


async def build_configuration(db: AsyncSession, data: AgentCreate) -> dict:
    models = {item["model_id"] for item in model_catalog() if item["available"]}
    if data.model_id is not None and data.model_id not in models:
        raise ApiError(422, "models.unavailable", "Выберите модель из доступного каталога.")
    skills = []
    seen = set()
    for selection in data.skills:
        if selection.skill_id in seen:
            raise ApiError(422, "skills.duplicate", "Скилл указан несколько раз.")
        seen.add(selection.skill_id)
        version = await db.scalar(
            select(SkillVersionModel).where(
                SkillVersionModel.skill_id == selection.skill_id,
                SkillVersionModel.version == selection.version,
            )
        )
        if version is None:
            raise ApiError(422, "skills.version-not-found", "Версия скилла не найдена.")
        skills.append(
            {
                **selection.model_dump(),
                "skill_version_id": version.id,
                "instruction": version.instruction,
                "editable_instruction": (
                    selection.instruction_override
                    if selection.instruction_override is not None
                    else version.editable_instruction
                ),
            }
        )
    return {
        **data.model_dump(),
        "skills": skills,
        "limits": {"tool_calls": 3, "active_seconds": 60, "confirmation_seconds": 900},
    }


async def append_version(db: AsyncSession, agent: AgentModel, configuration: dict, number: int) -> AgentVersionModel:
    version = AgentVersionModel(agent_id=agent.id, version=number, configuration=deepcopy(configuration))
    db.add(version)
    await db.flush()
    for skill in configuration["skills"]:
        if skill["instruction_override"] is not None:
            db.add(
                AgentSkillOverrideModel(
                    agent_version_id=version.id,
                    skill_id=skill["skill_id"],
                    instruction=skill["instruction_override"],
                )
            )
    return version


async def create_agent(db: AsyncSession, owner_id: str, configuration: dict) -> tuple[AgentModel, AgentVersionModel]:
    occupied = set(
        (
            await db.scalars(
                select(AgentModel.slot).where(
                    AgentModel.owner_id == owner_id,
                    AgentModel.deleted_at.is_(None),
                )
            )
        ).all()
    )
    slot = next((slot for slot in range(1, 6) if slot not in occupied), None)
    if slot is None:
        raise ApiError(
            409, "agents.limit-reached", "Можно создать не более пяти агентов. Удалите одного, чтобы освободить место."
        )
    agent = AgentModel(
        owner_id=owner_id,
        slot=slot,
        **{key: configuration[key] for key in ("name", "task_type", "subject", "grade")},
    )
    db.add(agent)
    await db.flush()
    return agent, await append_version(db, agent, configuration, 1)


def agent_response(agent: AgentModel, version: AgentVersionModel) -> dict:
    return {
        "id": agent.id,
        "epoch": agent.epoch,
        "version_id": version.id,
        "version": version.version,
        "created_at": agent.created_at,
        "updated_at": agent.updated_at,
        **version.configuration,
    }


async def clear_agent_data(db: AsyncSession, agent: AgentModel) -> None:
    now = timestamp()
    # LM02 tables are present in the shared checkout. Invalidate running work
    # atomically with the epoch change; completed traces remain historical.
    await db.execute(
        update(LabRunModel)
        .where(
            LabRunModel.owner_id == agent.owner_id,
            LabRunModel.agent_id == agent.id,
            LabRunModel.status.in_(("queued", "running", "awaiting_confirmation")),
        )
        .values(status="cancelled", stop_reason="agent_reset", completed_at_utc=now, updated_at_utc=now)
    )
    await db.execute(
        update(LabPendingActionModel)
        .where(
            LabPendingActionModel.owner_id == agent.owner_id,
            LabPendingActionModel.agent_id == agent.id,
            LabPendingActionModel.status == "pending",
        )
        .values(status="cancelled", resolved_at_utc=now)
    )
    # Dependency order also works when SQLite foreign_keys are enabled.
    for model in (MessageModel, ConversationModel, MaterialModel, MemoryEntryModel):
        await db.execute(delete(model).where(model.agent_id == agent.id, model.owner_id == agent.owner_id))
    agent.epoch += 1
    agent.updated_at = now
