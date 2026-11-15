from copy import deepcopy
from typing import Annotated

from fastapi import APIRouter, Depends, Response
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.errors import ApiError
from app.core.security import CurrentUser, get_current_user
from app.modules.lab.catalog import model_catalog
from app.modules.lab.models import (
    AgentModel,
    AgentSkillOverrideModel,
    AgentVersionModel,
    CourseProgressModel,
    SkillModel,
    SkillVersionModel,
    timestamp,
)
from app.modules.lab.schemas import AgentCopy, AgentCreate, AgentPatch, CourseProgressInput
from app.modules.lab.service import (
    agent_response,
    append_version,
    build_configuration,
    clear_agent_data,
    create_agent,
    latest_version,
    lock_owner,
    owned_agent,
)

router = APIRouter(prefix="/lab/v1", tags=["lab"])
Db = Annotated[AsyncSession, Depends(get_db)]
User = Annotated[CurrentUser, Depends(get_current_user)]


@router.get("/agents")
async def list_agents(db: Db, user: User):
    # One joined query returns consistent agent/version pairs without N+1.
    latest = (
        select(
            AgentVersionModel.agent_id,
            func.max(AgentVersionModel.version).label("version"),
        )
        .join(AgentModel, AgentModel.id == AgentVersionModel.agent_id)
        .where(
            AgentModel.owner_id == user.user_id,
            AgentModel.deleted_at.is_(None),
        )
        .group_by(AgentVersionModel.agent_id)
        .subquery()
    )
    rows = (
        await db.execute(
            select(AgentModel, AgentVersionModel)
            .join(
                AgentVersionModel,
                AgentVersionModel.agent_id == AgentModel.id,
            )
            .join(
                latest,
                (latest.c.agent_id == AgentModel.id) & (latest.c.version == AgentVersionModel.version),
            )
            .where(
                AgentModel.owner_id == user.user_id,
                AgentModel.deleted_at.is_(None),
            )
            .order_by(AgentModel.slot, AgentVersionModel.version.desc())
        )
    ).all()
    agents = {}
    for agent, version in rows:
        if agent.id not in agents:
            agents[agent.id] = agent_response(agent, version)
    return {"agents": list(agents.values()), "limit": 5}


@router.post("/agents", status_code=201)
async def post_agent(payload: AgentCreate, db: Db, user: User):
    await lock_owner(db, user.user_id)
    configuration = await build_configuration(db, payload)
    agent, version = await create_agent(db, user.user_id, configuration)
    await db.commit()
    return agent_response(agent, version)


@router.get("/agents/{agent_id}")
async def get_agent(agent_id: str, db: Db, user: User):
    # Use the list's single-statement snapshot, scoped to the requested object.
    row = (
        await db.execute(
            select(AgentModel, AgentVersionModel)
            .join(
                AgentVersionModel,
                AgentVersionModel.agent_id == AgentModel.id,
            )
            .where(
                AgentModel.id == agent_id,
                AgentModel.owner_id == user.user_id,
                AgentModel.deleted_at.is_(None),
            )
            .order_by(AgentVersionModel.version.desc())
            .limit(1)
        )
    ).first()
    if row is None:
        raise ApiError(404, "agents.not-found", "Агент не найден.")
    return agent_response(*row)


@router.patch("/agents/{agent_id}")
async def patch_agent(agent_id: str, payload: AgentPatch, db: Db, user: User):
    await lock_owner(db, user.user_id)
    agent = await owned_agent(db, user.user_id, agent_id)
    previous = await latest_version(db, agent.id)
    changes = payload.model_dump(exclude_unset=True)
    if any(value is None and key != "model_id" for key, value in changes.items()):
        raise ApiError(422, "request.invalid", "Поля настроек не могут быть null.")
    raw = {key: previous.configuration[key] for key in AgentCreate.model_fields}
    # Catalog text is already frozen in the previous version; accept only selection fields.
    raw["skills"] = [
        {key: skill[key] for key in ("skill_id", "version", "instruction_override")} for skill in raw["skills"]
    ]
    configuration = await build_configuration(db, AgentCreate.model_validate({**raw, **changes}))
    version = previous
    if configuration != previous.configuration:
        version = await append_version(db, agent, configuration, previous.version + 1)
        for key in ("name", "task_type", "subject", "grade"):
            setattr(agent, key, configuration[key])
        agent.updated_at = timestamp()
    await db.commit()
    return agent_response(agent, version)


@router.post("/agents/{agent_id}/copy", status_code=201)
async def copy_agent(agent_id: str, db: Db, user: User, payload: AgentCopy | None = None):
    await lock_owner(db, user.user_id)
    source = await owned_agent(db, user.user_id, agent_id)
    configuration = deepcopy((await latest_version(db, source.id)).configuration)
    configuration["name"] = payload.name if payload and payload.name else f"{source.name[:194]} копия"
    agent, version = await create_agent(db, user.user_id, configuration)
    await db.commit()
    return agent_response(agent, version)


@router.post("/agents/{agent_id}/reset")
async def reset_agent(agent_id: str, db: Db, user: User):
    await lock_owner(db, user.user_id)
    agent = await owned_agent(db, user.user_id, agent_id)
    await clear_agent_data(db, agent)
    version = await latest_version(db, agent.id)
    await db.commit()
    return agent_response(agent, version)


@router.delete("/agents/{agent_id}", status_code=204)
async def delete_agent(agent_id: str, db: Db, user: User):
    await lock_owner(db, user.user_id)
    agent = await owned_agent(db, user.user_id, agent_id, deleted=True)
    if agent.deleted_at is None:
        await clear_agent_data(db, agent)
        version_ids = select(AgentVersionModel.id).where(AgentVersionModel.agent_id == agent.id)
        await db.execute(
            delete(AgentSkillOverrideModel).where(AgentSkillOverrideModel.agent_version_id.in_(version_ids))
        )
        await db.execute(delete(AgentVersionModel).where(AgentVersionModel.agent_id == agent.id))
        agent.deleted_at = timestamp()
        agent.slot = None
    await db.commit()
    return Response(status_code=204)


@router.get("/models")
async def get_models(user: User):
    return {"models": model_catalog()}


@router.get("/skills")
async def get_skills(db: Db, user: User):
    rows = (
        await db.execute(
            select(SkillModel, SkillVersionModel)
            .join(
                SkillVersionModel,
                SkillVersionModel.skill_id == SkillModel.id,
            )
            .order_by(SkillModel.id, SkillVersionModel.version)
        )
    ).all()
    return {
        "skills": [
            {
                "skill_id": skill.id,
                "name": skill.name,
                "description": skill.description,
                "version": version.version,
                "version_id": version.id,
                "instruction": version.instruction,
                "editable_instruction": version.editable_instruction,
            }
            for skill, version in rows
        ]
    }


def progress_response(progress: CourseProgressModel | None) -> dict:
    if progress is None:
        return {"course_version": "0.2", "current_lesson": 1, "completed_lessons": [], "updated_at": None}
    return {
        key: getattr(progress, key)
        for key in (
            "course_version",
            "current_lesson",
            "completed_lessons",
            "updated_at",
        )
    }


@router.get("/course/progress")
async def get_progress(db: Db, user: User):
    return progress_response(await db.get(CourseProgressModel, user.user_id))


@router.put("/course/progress")
async def put_progress(payload: CourseProgressInput, db: Db, user: User):
    await lock_owner(db, user.user_id)
    progress = await db.get(CourseProgressModel, user.user_id)
    if progress is None:
        progress = CourseProgressModel(owner_id=user.user_id, completed_lessons=[])
        db.add(progress)
    progress.course_version = payload.course_version
    progress.current_lesson = payload.current_lesson
    progress.completed_lessons = sorted(set(progress.completed_lessons) | set(payload.completed_lessons))
    progress.updated_at = timestamp()
    await db.commit()
    return progress_response(progress)
