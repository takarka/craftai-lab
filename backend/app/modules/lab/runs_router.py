from __future__ import annotations

import json
import uuid
from dataclasses import replace
from datetime import datetime, timedelta
from typing import Any, AsyncGenerator, Callable

from fastapi import APIRouter, Depends, Header, Query, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy import and_, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.errors import ApiError
from app.core.idempotency import check_idempotency, compute_request_hash, save_idempotency
from app.core.security import CurrentUser, format_utc, get_current_user, utc_now
from app.modules.lab.catalog import model_catalog
from app.modules.lab.context_assembler import HistoryMessage, SkillContextItem
from app.modules.lab.harness import AgentSnapshot, LabHarness
from app.modules.lab.model_provider import DEFAULT_LAB_MODELS, ModelDescriptor, OpenRouterModelProvider
from app.modules.lab.models import AgentModel
from app.modules.lab.resources_router import load_agent_context_data
from app.modules.lab.runtime_models import (
    LabPendingActionModel,
    LabRunEventModel,
    LabRunModel,
)
from app.modules.lab.service import latest_version, owned_agent
from app.modules.mcp import MaterialsToolExecutor

router = APIRouter(prefix="/lab/v1", tags=["lab-runs"])


class CreateRunRequest(BaseModel):
    prompt: str = Field(min_length=1, max_length=10000)
    conversation_id: str | None = None
    dialogue: bool = False
    image_data_uris: list[str] = Field(default_factory=list, max_length=3)


class ResolveActionRequest(BaseModel):
    decision: str = Field(pattern="^(approve|deny)$")
    params: dict[str, Any] | None = None


async def default_get_agent_snapshot(
    *,
    db: AsyncSession,
    owner_id: str,
    agent_id: str,
) -> AgentSnapshot:
    """Resolve current agent version + Phase 3 memory/skills/materials into an AgentSnapshot."""
    agent = await owned_agent(db, owner_id, agent_id)
    version = await latest_version(db, agent.id)
    cfg = version.configuration or {}

    model_id = cfg.get("model_id")
    if not model_id:
        available = [m["model_id"] for m in model_catalog() if m.get("available") and m.get("model_id")]
        if available:
            model_id = available[0]
        else:
            raise ApiError(
                status_code=503,
                code="model.not-configured",
                message="На сервере не настроены модели. Обратитесь к администратору.",
            )

    perms = cfg.get("permissions") or {}
    allow_save = bool(perms.get("save_material", cfg.get("allow_save", False)))
    allow_search = bool(perms.get("search_materials", cfg.get("allow_search", False)))

    version_skills: list[SkillContextItem] = []
    for sk in cfg.get("skills") or []:
        version_skills.append(
            SkillContextItem(
                slug=str(sk.get("skill_id") or ""),
                title=str(sk.get("skill_id") or ""),
                content=str(sk.get("instruction") or ""),
                override_text=sk.get("editable_instruction") or None,
            )
        )

    extra_skills, memory_facts, knowledge_chunks = await load_agent_context_data(
        db,
        owner_id=owner_id,
        agent_id=agent.id,
        allow_search=allow_search,
    )
    existing_slugs = {s.slug for s in version_skills}
    for s in extra_skills:
        if s.slug not in existing_slugs:
            version_skills.append(s)

    limits = cfg.get("limits") or {}
    return AgentSnapshot(
        agent_id=agent.id,
        agent_version_id=version.id,
        owner_id=owner_id,
        epoch=agent.epoch,
        model_id=str(model_id),
        instruction=cfg.get("instruction") or None,
        skills=version_skills,
        knowledge_chunks=knowledge_chunks,
        memory_facts=memory_facts,
        allow_save=allow_save,
        allow_search=allow_search,
        max_tool_calls=int(limits.get("tool_calls", 3)),
        active_timeout_seconds=int(limits.get("active_seconds", 60)),
        confirmation_ttl_seconds=int(limits.get("confirmation_seconds", 900)),
    )


async def _lookup_agent_epoch(db: AsyncSession, owner_id: str, agent_id: str) -> int | None:
    return (
        await db.execute(
            select(AgentModel.epoch).where(
                AgentModel.id == agent_id,
                AgentModel.owner_id == owner_id,
                AgentModel.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()


def _build_runtime_models_catalog() -> dict[str, ModelDescriptor]:
    catalog: dict[str, ModelDescriptor] = dict(DEFAULT_LAB_MODELS)
    for item in model_catalog():
        mid = item.get("model_id")
        if mid and item.get("available"):
            base = catalog.get(mid)
            catalog[mid] = ModelDescriptor(
                model_id=mid,
                display_name=base.display_name if base else mid,
                supports_tools=bool(item.get("supports_tools", False)),
                supports_vision=bool(item.get("supports_vision", False)),
                context_window=base.context_window if base else 128000,
                input_cost_per_1m_usd=base.input_cost_per_1m_usd if base else 0.0,
                output_cost_per_1m_usd=base.output_cost_per_1m_usd if base else 0.0,
            )
    return catalog


def get_harness() -> LabHarness:
    return LabHarness(
        model_provider=OpenRouterModelProvider(),
        tool_executor=MaterialsToolExecutor(),
        models_catalog=_build_runtime_models_catalog(),
        epoch_lookup=_lookup_agent_epoch,
    )


def get_snapshot_resolver() -> Callable[..., Any]:
    return default_get_agent_snapshot


def _serialize_run(
    run: LabRunModel,
    events: list[LabRunEventModel] | None = None,
    pending_actions: list[LabPendingActionModel] | None = None,
) -> dict[str, Any]:
    data: dict[str, Any] = {
        "id": run.id,
        "agent_id": run.agent_id,
        "agent_version_id": run.agent_version_id,
        "conversation_id": run.conversation_id,
        "epoch": run.epoch,
        "model_id": run.model_id,
        "status": run.status,
        "stop_reason": run.stop_reason,
        "final_output": run.final_output,
        "error_code": run.error_code,
        "error_message": run.error_message,
        "tool_calls_count": run.tool_calls_count,
        "active_elapsed_ms": run.active_elapsed_ms,
        "created_at_utc": run.created_at_utc,
        "updated_at_utc": run.updated_at_utc,
        "completed_at_utc": run.completed_at_utc,
    }
    if events is not None:
        data["events"] = [
            {
                "id": e.id,
                "sequence": e.sequence,
                "epoch": e.epoch,
                "event_type": e.event_type,
                "payload": e.payload_json,
                "created_at_utc": e.created_at_utc,
            }
            for e in events
        ]
    if pending_actions is not None:
        data["pending_actions"] = [
            {
                "id": a.id,
                "tool_call_id": a.tool_call_id,
                "tool_name": a.tool_name,
                "params": a.params_json,
                "params_hash": a.params_hash,
                "status": a.status,
                "expires_at_utc": a.expires_at_utc,
                "resolved_at_utc": a.resolved_at_utc,
            }
            for a in pending_actions
        ]
    return data


async def _load_owned_run(
    db: AsyncSession,
    *,
    run_id: str,
    owner_id: str,
) -> LabRunModel:
    stmt = select(LabRunModel).where(LabRunModel.id == run_id, LabRunModel.owner_id == owner_id)
    run = (await db.execute(stmt)).scalar_one_or_none()
    if run is None:
        raise ApiError(status_code=404, code="run.not-found", message="Запуск не найден.")
    return run


def _dialogue_id(owner_id: str, agent_id: str, epoch: int) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"craftai/lab/dialogue/{owner_id}/{agent_id}/{epoch}"))


def _dialogue_rows(owner_id: str, agent_id: str, epoch: int):
    return select(LabRunModel).where(
        LabRunModel.owner_id == owner_id,
        LabRunModel.agent_id == agent_id,
        LabRunModel.epoch == epoch,
        LabRunModel.conversation_id == _dialogue_id(owner_id, agent_id, epoch),
        LabRunModel.version_snapshot_json["dialogue_request_hash"].as_string().is_not(None),
    )


async def _run_payload(db: AsyncSession, run: LabRunModel) -> dict[str, Any]:
    events = (await db.scalars(
        select(LabRunEventModel)
        .where(LabRunEventModel.run_id == run.id)
        .order_by(LabRunEventModel.sequence)
    )).all()
    actions = (await db.scalars(
        select(LabPendingActionModel).where(LabPendingActionModel.run_id == run.id)
    )).all()
    return _serialize_run(run, events=list(events), pending_actions=list(actions))


@router.get("/agents/{agent_id}/dialogue")
async def get_agent_dialogue(
    agent_id: str,
    before: str | None = Query(default=None, max_length=36),
    limit: int = Query(default=30, ge=1, le=100),
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    owner = current_user.user_id
    agent = await owned_agent(db, owner, agent_id)
    stmt = _dialogue_rows(owner, agent_id, agent.epoch)
    if before:
        cursor = (await db.scalars(stmt.where(LabRunModel.id == before))).one_or_none()
        if cursor is None:
            raise ApiError(status_code=404, code="dialogue.cursor-not-found", message="Позиция диалога не найдена.")
        stmt = stmt.where(or_(
            LabRunModel.created_at_utc < cursor.created_at_utc,
            and_(LabRunModel.created_at_utc == cursor.created_at_utc, LabRunModel.id < cursor.id),
        ))
    rows = list((await db.scalars(stmt.order_by(
        LabRunModel.created_at_utc.desc(), LabRunModel.id.desc(),
    ).limit(limit + 1))).all())
    page = rows[:limit]
    turns = []
    for item in reversed(page):
        value = (
            await _run_payload(db, item)
            if item.status in ("running", "awaiting_confirmation") else _serialize_run(item)
        )
        turns.append({"prompt": item.user_prompt, "run": value})
    return {
        "conversation_id": _dialogue_id(owner, agent_id, agent.epoch),
        "turns": turns,
        "next_before": page[-1].id if len(rows) > limit else None,
    }


async def _create_dialogue_run(
    db: AsyncSession,
    *,
    agent_id: str,
    owner_id: str,
    body: CreateRunRequest,
    key: str | None,
    harness: LabHarness,
    resolve_snapshot: Callable[..., Any],
) -> JSONResponse:
    if not key or not key.strip() or len(key.strip()) > 100:
        raise ApiError(status_code=422, code="dialogue.idempotency-required", message="Нужен ключ отправки сообщения.")
    # A short write lock serializes admission on SQLite and PostgreSQL. start_run
    # commits the accepted run before it awaits the provider, releasing the lock.
    await db.execute(
        update(AgentModel)
        .where(
            AgentModel.id == agent_id, AgentModel.owner_id == owner_id,
            AgentModel.deleted_at.is_(None),
        )
        .values(epoch=AgentModel.epoch)
    )
    agent = await owned_agent(db, owner_id, agent_id)
    conversation_id = _dialogue_id(owner_id, agent_id, agent.epoch)
    if body.conversation_id != conversation_id:
        raise ApiError(status_code=409, code="dialogue.changed", message="Диалог изменился. Откройте его заново.")
    request_hash = compute_request_hash({"prompt": body.prompt, "images": body.image_data_uris})
    run_id = str(uuid.uuid5(uuid.UUID(conversation_id), key.strip()))
    scoped = _dialogue_rows(owner_id, agent_id, agent.epoch)
    existing = (await db.scalars(scoped.where(LabRunModel.id == run_id))).one_or_none()
    if existing is not None:
        if existing.version_snapshot_json.get("dialogue_request_hash") != request_hash:
            raise ApiError(
                status_code=409, code="idempotency.key-reused",
                message="Ключ отправки уже использован для другого сообщения.",
            )
        payload = await _run_payload(db, existing)
        await db.rollback()
        return JSONResponse(status_code=201, content=payload)
    active = await db.scalar(
        scoped.where(LabRunModel.status.in_(("running", "awaiting_confirmation"))).limit(1)
    )
    if active is not None:
        raise ApiError(status_code=409, code="dialogue.busy", message="Предыдущий ответ ещё не завершён.")
    snapshot = await resolve_snapshot(db=db, owner_id=owner_id, agent_id=agent_id)
    # The common timestamp formatter is second-grained. Keep a strictly
    # increasing microsecond timestamp for dialogue ordering under the lock.
    latest_at = await db.scalar(scoped.with_only_columns(
        LabRunModel.created_at_utc,
    ).order_by(LabRunModel.created_at_utc.desc()).limit(1))
    started = utc_now()
    if latest_at:
        started = max(started, datetime.fromisoformat(latest_at) + timedelta(microseconds=1))
    created_at = started.isoformat(timespec="microseconds").replace("+00:00", "Z")
    history: list[HistoryMessage] = []
    completed = await db.scalars(scoped.where(
        LabRunModel.status == "completed", LabRunModel.stop_reason == "completed",
    ).order_by(LabRunModel.created_at_utc, LabRunModel.id))
    for prior in completed:
        history.append(HistoryMessage("user", prior.user_prompt))
        if prior.final_output:
            history.append(HistoryMessage("assistant", prior.final_output))
    run = await harness.start_run(
        db,
        snapshot=replace(snapshot, conversation_history=history),
        user_prompt=body.prompt,
        conversation_id=conversation_id,
        idempotency_key=key.strip(),
        image_data_uris=body.image_data_uris or None,
        dialogue_run_id=run_id,
        dialogue_request_hash=request_hash,
        dialogue_created_at=created_at,
    )
    return JSONResponse(status_code=201, content=await _run_payload(db, run))


@router.post("/agents/{agent_id}/runs")
async def create_agent_run(
    agent_id: str,
    body: CreateRunRequest,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    harness: LabHarness = Depends(get_harness),
    resolve_snapshot: Callable[..., Any] = Depends(get_snapshot_resolver),
) -> JSONResponse:
    if body.dialogue:
        return await _create_dialogue_run(
            db, agent_id=agent_id, owner_id=current_user.user_id, body=body,
            key=idempotency_key, harness=harness, resolve_snapshot=resolve_snapshot,
        )
    route = f"POST /lab/v1/agents/{agent_id}/runs"
    req_hash = compute_request_hash(
        {
            "agent_id": agent_id,
            "prompt": body.prompt,
            "conversation_id": body.conversation_id,
            "image_count": len(body.image_data_uris),
        }
    )
    cached = await check_idempotency(
        db,
        user_id=current_user.user_id,
        route=route,
        key=idempotency_key,
        request_hash=req_hash,
    )
    if cached is not None:
        status_code, response_json = cached
        return JSONResponse(status_code=status_code, content=response_json)

    snapshot = await resolve_snapshot(db=db, owner_id=current_user.user_id, agent_id=agent_id)
    run = await harness.start_run(
        db,
        snapshot=snapshot,
        user_prompt=body.prompt,
        conversation_id=body.conversation_id,
        idempotency_key=idempotency_key,
        image_data_uris=body.image_data_uris or None,
    )

    events = (
        await db.execute(
            select(LabRunEventModel)
            .where(LabRunEventModel.run_id == run.id)
            .order_by(LabRunEventModel.sequence.asc())
        )
    ).scalars().all()
    actions = (
        await db.execute(
            select(LabPendingActionModel).where(LabPendingActionModel.run_id == run.id)
        )
    ).scalars().all()

    payload = _serialize_run(run, events=list(events), pending_actions=list(actions))
    await save_idempotency(
        db,
        user_id=current_user.user_id,
        route=route,
        key=idempotency_key,
        request_hash=req_hash,
        status_code=201,
        response_json=payload,
    )
    return JSONResponse(status_code=201, content=payload)


@router.get("/runs/{run_id}")
async def get_run(
    run_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    run = await _load_owned_run(db, run_id=run_id, owner_id=current_user.user_id)
    events = (
        await db.execute(
            select(LabRunEventModel)
            .where(LabRunEventModel.run_id == run.id)
            .order_by(LabRunEventModel.sequence.asc())
        )
    ).scalars().all()
    actions = (
        await db.execute(
            select(LabPendingActionModel).where(LabPendingActionModel.run_id == run.id)
        )
    ).scalars().all()
    return _serialize_run(run, events=list(events), pending_actions=list(actions))


def _format_sse(event_type: str, sequence: int, payload: dict[str, Any]) -> str:
    data = json.dumps(payload, ensure_ascii=False)
    return f"event: {event_type}\nid: evt_{sequence}\ndata: {data}\n\n"


@router.get("/runs/{run_id}/stream")
async def stream_run_events(
    run_id: str,
    request: Request,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> StreamingResponse:
    run = await _load_owned_run(db, run_id=run_id, owner_id=current_user.user_id)

    last_event_id = request.headers.get("Last-Event-ID", "")
    min_seq = 0
    if last_event_id.startswith("evt_"):
        with_num = last_event_id[4:]
        if with_num.isdigit():
            min_seq = int(with_num)

    events = (
        await db.execute(
            select(LabRunEventModel)
            .where(
                LabRunEventModel.run_id == run.id,
                LabRunEventModel.sequence > min_seq,
            )
            .order_by(LabRunEventModel.sequence.asc())
        )
    ).scalars().all()

    async def event_generator() -> AsyncGenerator[str, None]:
        for evt in events:
            yield _format_sse(
                evt.event_type,
                evt.sequence,
                {
                    "id": evt.id,
                    "sequence": evt.sequence,
                    "epoch": evt.epoch,
                    "event_type": evt.event_type,
                    "payload": evt.payload_json,
                    "created_at_utc": evt.created_at_utc,
                },
            )

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.post("/runs/{run_id}/cancel")
async def cancel_run(
    run_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    harness: LabHarness = Depends(get_harness),
) -> dict[str, Any]:
    run = await _load_owned_run(db, run_id=run_id, owner_id=current_user.user_id)
    if run.status in ("completed", "failed", "cancelled"):
        return _serialize_run(run)

    now_str = format_utc(utc_now())
    run.status = "cancelled"
    run.stop_reason = "cancelled"
    run.updated_at_utc = now_str
    run.completed_at_utc = now_str

    pending = (
        await db.execute(
            select(LabPendingActionModel).where(
                LabPendingActionModel.run_id == run.id,
                LabPendingActionModel.status == "pending",
            )
        )
    ).scalars().all()
    for action in pending:
        action.status = "cancelled"
        action.resolved_at_utc = now_str

    await db.commit()
    await harness.append_event(db, run, "run_cancelled", {"run_id": run.id, "stop_reason": "cancelled"})
    return _serialize_run(run)


@router.post("/runs/{run_id}/actions/{action_id}")
async def resolve_run_action(
    run_id: str,
    action_id: str,
    body: ResolveActionRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    harness: LabHarness = Depends(get_harness),
) -> dict[str, Any]:
    run = await _load_owned_run(db, run_id=run_id, owner_id=current_user.user_id)
    action = (
        await db.execute(
            select(LabPendingActionModel).where(
                LabPendingActionModel.id == action_id,
                LabPendingActionModel.run_id == run.id,
                LabPendingActionModel.owner_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if action is None:
        raise ApiError(status_code=404, code="action.not-found", message="Запрос подтверждения не найден.")

    try:
        updated_run = await harness.resolve_action(
            db,
            run=run,
            action=action,
            decision=body.decision,
            params=body.params,
        )
    except ApiError as error:
        if not run.version_snapshot_json.get("dialogue_request_hash") or run.status != "running":
            raise
        updated_run = await harness.fail_dialogue_run(db, run, error.code, error.message)
    events = (
        await db.execute(
            select(LabRunEventModel)
            .where(LabRunEventModel.run_id == updated_run.id)
            .order_by(LabRunEventModel.sequence.asc())
        )
    ).scalars().all()
    actions = (
        await db.execute(
            select(LabPendingActionModel).where(LabPendingActionModel.run_id == updated_run.id)
        )
    ).scalars().all()
    return _serialize_run(updated_run, events=list(events), pending_actions=list(actions))
