from __future__ import annotations

import uuid
from typing import Any

from fastapi import APIRouter, Depends, Header
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.core.database import SessionLocal, get_db
from app.core.errors import ApiError
from app.core.security import CurrentUser, format_utc, get_current_user, utc_now
from app.modules.lab.models import AgentModel, MaterialModel

router = APIRouter(tags=["mcp"])

MCP_TOOLS: list[dict[str, Any]] = [
    {
        "name": "save_material",
        "description": "Сохранить учебный материал в изолированное хранилище текущего агента.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "Название материала"},
                "content": {"type": "string", "description": "Текст материала"},
            },
            "required": ["title", "content"],
        },
    },
    {
        "name": "search_materials",
        "description": "Найти ранее сохранённые материалы текущего агента по ключевым словам.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Поисковый запрос"},
            },
            "required": ["query"],
        },
    },
]


async def require_agent_epoch(db: AsyncSession, *, owner_id: str, agent_id: str) -> int:
    epoch = await db.scalar(select(AgentModel.epoch).where(
        AgentModel.id == agent_id,
        AgentModel.owner_id == owner_id,
        AgentModel.deleted_at.is_(None),
    ))
    if epoch is None:
        raise ApiError(status_code=404, code="agents.not-found", message="Агент не найден.")
    return epoch


async def save_material_record(
    db: AsyncSession,
    *,
    owner_id: str,
    agent_id: str,
    title: str,
    content: str,
    source: str = "text",
) -> MaterialModel:
    clean_title = title.strip()[:200] or "Без названия"
    clean_content = content.strip()
    if not clean_content:
        raise ApiError(
            status_code=422,
            code="material.empty-content",
            message="Текст материала не может быть пустым.",
        )
    if len(clean_content) > 10000:
        raise ApiError(
            status_code=422,
            code="material.too-long",
            message="Текст материала превышает 10 000 знаков.",
        )

    agent_epoch = await require_agent_epoch(db, owner_id=owner_id, agent_id=agent_id)

    row = MaterialModel(
        id=str(uuid.uuid4()),
        owner_id=owner_id,
        agent_id=agent_id,
        epoch=agent_epoch,
        title=clean_title,
        text=clean_content,
        source=source if source in ("text", "photo") else "text",
        created_at=format_utc(utc_now()),
    )
    db.add(row)
    await db.commit()
    return row


async def search_materials_records(
    db: AsyncSession,
    *,
    owner_id: str,
    agent_id: str,
    query: str,
    limit: int = 10,
) -> list[MaterialModel]:
    await require_agent_epoch(db, owner_id=owner_id, agent_id=agent_id)
    # Strictly isolated by (owner_id, agent_id) from run context; never from model arguments.
    stmt = (
        select(MaterialModel)
        .where(
            MaterialModel.owner_id == owner_id,
            MaterialModel.agent_id == agent_id,
        )
        .order_by(MaterialModel.created_at.desc())
    )
    rows = (await db.execute(stmt)).scalars().all()
    q = query.strip().lower()
    if not q:
        return list(rows[:limit])
    matched = [r for r in rows if q in r.title.lower() or q in r.text.lower()]
    return matched[:limit]


class MaterialsToolExecutor:
    """Harness ToolExecutor backed by MaterialModel, isolated by (owner_id, agent_id)."""

    def __init__(self, session_factory: async_sessionmaker[AsyncSession] = SessionLocal) -> None:
        self._session_factory = session_factory

    async def execute(
        self,
        *,
        owner_id: str,
        agent_id: str,
        tool_name: str,
        params: dict[str, Any],
    ) -> dict[str, Any]:
        # Explicitly ignore any owner_id / agent_id supplied in model arguments.
        async with self._session_factory() as db:
            if tool_name == "save_material":
                row = await save_material_record(
                    db,
                    owner_id=owner_id,
                    agent_id=agent_id,
                    title=str(params.get("title") or ""),
                    content=str(params.get("content") or ""),
                    source="text",
                )
                return {
                    "status": "saved",
                    "material_id": row.id,
                    "title": row.title,
                }

            if tool_name == "search_materials":
                rows = await search_materials_records(
                    db,
                    owner_id=owner_id,
                    agent_id=agent_id,
                    query=str(params.get("query") or ""),
                )
                return {
                    "status": "ok",
                    "items": [
                        {
                            "material_id": r.id,
                            "title": r.title,
                            "content": r.text,
                            "source": r.source,
                        }
                        for r in rows
                    ],
                }

        raise ApiError(
            status_code=400,
            code="tool.unknown",
            message=f"Неизвестный инструмент: {tool_name}",
        )


@router.post("/mcp/v1")
async def handle_mcp_jsonrpc(
    payload: dict[str, Any],
    x_agent_id: str | None = Header(default=None, alias="X-Agent-Id"),
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    rpc_id = payload.get("id")
    method = str(payload.get("method") or "")
    params = payload.get("params") or {}

    if method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": rpc_id,
            "result": {"tools": MCP_TOOLS},
        }

    if method == "tools/call":
        tool_name = str(params.get("name") or "")
        arguments = params.get("arguments") or {}
        if not isinstance(arguments, dict):
            arguments = {}

        agent_id = (x_agent_id or "").strip() or "default"

        if tool_name == "save_material":
            row = await save_material_record(
                db,
                owner_id=current_user.user_id,
                agent_id=agent_id,
                title=str(arguments.get("title") or ""),
                content=str(arguments.get("content") or ""),
                source="text",
            )
            return {
                "jsonrpc": "2.0",
                "id": rpc_id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": f"Материал «{row.title}» сохранён (ID: {row.id}).",
                        }
                    ],
                    "material_id": row.id,
                },
            }

        if tool_name == "search_materials":
            rows = await search_materials_records(
                db,
                owner_id=current_user.user_id,
                agent_id=agent_id,
                query=str(arguments.get("query") or ""),
            )
            return {
                "jsonrpc": "2.0",
                "id": rpc_id,
                "result": {
                    "items": [
                        {
                            "material_id": r.id,
                            "title": r.title,
                            "content": r.text,
                            "source": r.source,
                        }
                        for r in rows
                    ]
                },
            }

        return {
            "jsonrpc": "2.0",
            "id": rpc_id,
            "error": {"code": -32601, "message": f"Unknown tool: {tool_name}"},
        }

    return {
        "jsonrpc": "2.0",
        "id": rpc_id,
        "error": {"code": -32601, "message": f"Unknown method: {method}"},
    }
