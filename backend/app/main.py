from __future__ import annotations

import asyncio
import contextlib
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncGenerator

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import delete, select

from app.core.config import settings
from app.core.database import (
    ArtifactModel,
    AttachmentModel,
    Base,
    IdempotencyRecordModel,
    SessionLocal,
    UserModel,
    engine,
)
from app.core.errors import get_request_id, register_exception_handlers
from app.core.security import format_utc, hash_password, utc_now
from app.modules import auth, calendar, documents, mcp, models_and_chat, schedules


async def seed_default_dev_user() -> None:
    async with SessionLocal() as db:
        res = await db.execute(
            select(UserModel).where(UserModel.email == "local-dev@craft-ai.local")
        )
        existing = res.scalar_one_or_none()
        if existing is None:
            user = UserModel(
                id=str(uuid.uuid4()),
                email="local-dev@craft-ai.local",
                name="Local Developer",
                password_hash=hash_password("LocalDevPass123!"),
                role="SuperAdmin",
                must_change_password=False,
                terms_revision="2026.1-ru",
                privacy_revision="2026.1-ru",
                language="ru",
                created_at_utc=format_utc(utc_now()),
            )
            db.add(user)
            await db.commit()


async def cleanup_expired_resources() -> None:
    now_str = format_utc(utc_now())
    async with SessionLocal() as db:
        att_res = await db.execute(
            select(AttachmentModel).where(AttachmentModel.expires_at_utc < now_str)
        )
        for att in att_res.scalars().all():
            if att.storage_path:
                with contextlib.suppress(OSError):
                    Path(att.storage_path).unlink(missing_ok=True)
            await db.delete(att)

        art_res = await db.execute(
            select(ArtifactModel).where(ArtifactModel.expires_at_utc < now_str)
        )
        for art in art_res.scalars().all():
            with contextlib.suppress(OSError):
                Path(art.storage_path).unlink(missing_ok=True)
            await db.delete(art)

        await db.execute(
            delete(IdempotencyRecordModel).where(IdempotencyRecordModel.expires_at_utc < now_str)
        )
        await db.commit()


async def background_worker_loop(stop_event: asyncio.Event) -> None:
    while not stop_event.is_set():
        with contextlib.suppress(Exception):
            await schedules.run_scheduler_tick()
            await cleanup_expired_resources()
        try:
            await asyncio.wait_for(
                stop_event.wait(),
                timeout=max(5, settings.scheduler_tick_seconds),
            )
        except asyncio.TimeoutError:
            continue


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncGenerator[None, None]:
    Path(settings.storage_dir).mkdir(parents=True, exist_ok=True)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await seed_default_dev_user()

    stop_event = asyncio.Event()
    worker_task: asyncio.Task[None] | None = None
    if settings.enable_embedded_worker:
        worker_task = asyncio.create_task(background_worker_loop(stop_event))
    try:
        yield
    finally:
        stop_event.set()
        if worker_task is not None:
            worker_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await worker_task


app = FastAPI(
    title="Craft AI Builder Backend",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["ETag", "X-Request-Id", "Retry-After", "Accept-Ranges", "Content-Range"],
)


@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    request_id = get_request_id(request)
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers.setdefault("X-Request-Id", request_id)
    return response


register_exception_handlers(app)

app.include_router(auth.router)
app.include_router(models_and_chat.router)
app.include_router(calendar.router)
app.include_router(documents.router)
app.include_router(schedules.router)
app.include_router(mcp.router)


@app.get("/health", tags=["system"])
async def health_check() -> dict[str, str]:
    return {"status": "healthy"}
