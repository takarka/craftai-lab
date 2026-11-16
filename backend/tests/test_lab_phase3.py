from __future__ import annotations

import uuid
from datetime import timedelta
from pathlib import Path
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.database import Base, UserModel, get_db
from app.core.errors import register_exception_handlers
from app.core.security import create_access_token, format_utc, hash_password, utc_now
from app.modules.lab.harness import AgentSnapshot, LabHarness
from app.modules.lab.materials_models import LabPhotoUploadModel
from app.modules.lab.models import AgentModel, MaterialModel
from app.modules.lab.model_provider import ModelCompletionResult, ToolCallRequest
from app.modules.lab.photos import MAX_PHOTO_BYTES, cleanup_expired_lab_photos
from app.modules.lab.resources_router import (
    get_photo_extractor,
    load_agent_context_data,
    router as resources_router,
)
from app.modules.lab.runs_router import get_harness, get_snapshot_resolver, router as runs_router
from app.modules.mcp import MaterialsToolExecutor


class FakeModelProvider:
    def __init__(self, responses: list[ModelCompletionResult]) -> None:
        self._responses = list(responses)
        self.calls: list[dict[str, Any]] = []

    async def complete(
        self,
        *,
        model_id: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
    ) -> ModelCompletionResult:
        self.calls.append({"model_id": model_id, "messages": messages, "tools": tools})
        if not self._responses:
            return ModelCompletionResult(content="Готово.")
        return self._responses.pop(0)


class FakePhotoExtractor:
    async def extract_text(self, *, raw_bytes: bytes, mime_type: str) -> str:
        return "Распознанный текст контрольной работы"


@pytest.fixture
async def phase3_env(tmp_path: Path):
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", future=True)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)

    user_a = UserModel(
        id=str(uuid.uuid4()),
        email="p3-a@example.com",
        name="Teacher A",
        password_hash=hash_password("Pass123!"),
        role="Teacher",
        must_change_password=False,
        terms_revision="2026.1-ru",
        privacy_revision="2026.1-ru",
        language="ru",
        created_at_utc=format_utc(utc_now()),
    )
    user_b = UserModel(
        id=str(uuid.uuid4()),
        email="p3-b@example.com",
        name="Teacher B",
        password_hash=hash_password("Pass123!"),
        role="Teacher",
        must_change_password=False,
        terms_revision="2026.1-ru",
        privacy_revision="2026.1-ru",
        language="ru",
        created_at_utc=format_utc(utc_now()),
    )
    async with session_factory() as db:
        db.add_all([user_a, user_b])
        await db.flush()
        db.add_all(
            [
                AgentModel(id="agent-1", owner_id=user_a.id, slot=1, name="Агент 1"),
                AgentModel(id="agent-2", owner_id=user_a.id, slot=2, name="Агент 2"),
                AgentModel(id="agent-b-1", owner_id=user_b.id, slot=1, name="Агент B1"),
            ]
        )
        await db.commit()

    token_a, _ = create_access_token(
        user_id=user_a.id, email=user_a.email, name=user_a.name, role=user_a.role
    )
    token_b, _ = create_access_token(
        user_id=user_b.id, email=user_b.email, name=user_b.name, role=user_b.role
    )

    yield {
        "session_factory": session_factory,
        "user_a": user_a,
        "user_b": user_b,
        "token_a": token_a,
        "token_b": token_b,
        "tmp_path": tmp_path,
    }
    await engine.dispose()


def _build_phase3_app(
    session_factory: async_sessionmaker[AsyncSession],
    *,
    harness: LabHarness | None = None,
    snapshot_map: dict[str, AgentSnapshot] | None = None,
) -> FastAPI:
    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(resources_router)
    app.include_router(runs_router)

    async def override_get_db():
        async with session_factory() as db:
            yield db

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_photo_extractor] = lambda: FakePhotoExtractor()
    if harness is not None:
        app.dependency_overrides[get_harness] = lambda: harness
    if snapshot_map is not None:

        async def resolver(*, db: AsyncSession, owner_id: str, agent_id: str) -> AgentSnapshot:
            return snapshot_map[f"{owner_id}:{agent_id}"]

        app.dependency_overrides[get_snapshot_resolver] = lambda: resolver
    return app


@pytest.mark.asyncio
async def test_mcp_save_and_search_with_agent_and_user_isolation(phase3_env) -> None:
    session_factory = phase3_env["session_factory"]
    user_a = phase3_env["user_a"]
    user_b = phase3_env["user_b"]

    provider = FakeModelProvider(
        responses=[
            # Run 1 (agent-1): save_material
            ModelCompletionResult(
                content="",
                tool_calls=[
                    ToolCallRequest(
                        id="tc-save",
                        name="save_material",
                        arguments={"title": "Закон Ома", "content": "I = U / R"},
                    )
                ],
            ),
            ModelCompletionResult(content="Сохранено."),
            # Run 2 (agent-1): search_materials
            ModelCompletionResult(
                content="",
                tool_calls=[
                    ToolCallRequest(
                        id="tc-search-1",
                        name="search_materials",
                        arguments={"query": "Ома"},
                    )
                ],
            ),
            ModelCompletionResult(content="Найдено."),
            # Run 3 (agent-2 of user_a): tries to pass agent_id="agent-1" in args -> must NOT see agent-1's material
            ModelCompletionResult(
                content="",
                tool_calls=[
                    ToolCallRequest(
                        id="tc-search-2",
                        name="search_materials",
                        arguments={"query": "Ома", "agent_id": "agent-1"},
                    )
                ],
            ),
            ModelCompletionResult(content="Не найдено."),
            # Run 4 (agent-1 of user_b): must NOT see user_a's material
            ModelCompletionResult(
                content="",
                tool_calls=[
                    ToolCallRequest(
                        id="tc-search-3",
                        name="search_materials",
                        arguments={"query": "Ома"},
                    )
                ],
            ),
            ModelCompletionResult(content="Не найдено."),
        ]
    )
    executor = MaterialsToolExecutor(session_factory=session_factory)
    harness = LabHarness(model_provider=provider, tool_executor=executor)
    snapshots = {
        f"{user_a.id}:agent-1": AgentSnapshot(
            agent_id="agent-1",
            agent_version_id="v1",
            owner_id=user_a.id,
            epoch=1,
            model_id="google/gemini-2.5-flash",
            allow_save=True,
            allow_search=True,
        ),
        f"{user_a.id}:agent-2": AgentSnapshot(
            agent_id="agent-2",
            agent_version_id="v1",
            owner_id=user_a.id,
            epoch=1,
            model_id="google/gemini-2.5-flash",
            allow_search=True,
        ),
        f"{user_b.id}:agent-b-1": AgentSnapshot(
            agent_id="agent-b-1",
            agent_version_id="v1",
            owner_id=user_b.id,
            epoch=1,
            model_id="google/gemini-2.5-flash",
            allow_search=True,
        ),
    }
    app = _build_phase3_app(session_factory, harness=harness, snapshot_map=snapshots)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Save on agent-1 and approve
        r1 = (
            await client.post(
                "/lab/v1/agents/agent-1/runs",
                headers={"Authorization": f"Bearer {phase3_env['token_a']}"},
                json={"prompt": "Сохрани Закон Ома"},
            )
        ).json()
        action_id = r1["pending_actions"][0]["id"]
        r1_done = (
            await client.post(
                f"/lab/v1/runs/{r1['id']}/actions/{action_id}",
                headers={"Authorization": f"Bearer {phase3_env['token_a']}"},
                json={"decision": "approve"},
            )
        ).json()
        tool_evts = [e for e in r1_done["events"] if e["event_type"] == "tool_result"]
        material_id = tool_evts[0]["payload"]["result"]["material_id"]
        assert material_id

        # 2. Search in a new run on agent-1 -> finds material_id
        r2 = (
            await client.post(
                "/lab/v1/agents/agent-1/runs",
                headers={"Authorization": f"Bearer {phase3_env['token_a']}"},
                json={"prompt": "Найди про Ома"},
            )
        ).json()
        r2_res = [e for e in r2["events"] if e["event_type"] == "tool_result"][0]["payload"]["result"]
        assert len(r2_res["items"]) == 1
        assert r2_res["items"][0]["material_id"] == material_id

        # 3. Search on agent-2 of user_a -> empty
        r3 = (
            await client.post(
                "/lab/v1/agents/agent-2/runs",
                headers={"Authorization": f"Bearer {phase3_env['token_a']}"},
                json={"prompt": "Найди про Ома"},
            )
        ).json()
        r3_res = [e for e in r3["events"] if e["event_type"] == "tool_result"][0]["payload"]["result"]
        assert r3_res["items"] == []

        # 4. Search on user_b -> empty
        r4 = (
            await client.post(
                "/lab/v1/agents/agent-b-1/runs",
                headers={"Authorization": f"Bearer {phase3_env['token_b']}"},
                json={"prompt": "Найди про Ома"},
            )
        ).json()
        r4_res = [e for e in r4["events"] if e["event_type"] == "tool_result"][0]["payload"]["result"]
        assert r4_res["items"] == []


@pytest.mark.asyncio
async def test_photo_validation_magic_bytes_size_and_no_autosave(phase3_env, monkeypatch) -> None:
    monkeypatch.setattr("app.modules.lab.photos.settings.storage_dir", str(phase3_env["tmp_path"]))
    app = _build_phase3_app(phase3_env["session_factory"])

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        headers = {"Authorization": f"Bearer {phase3_env['token_a']}"}

        # 1. 11 MB -> 422
        oversized = b"\xff\xd8\xff\xe0" + (b"0" * (MAX_PHOTO_BYTES + 1024))
        r_big = await client.post(
            "/lab/v1/agents/agent-1/photos",
            headers=headers,
            files={"file": ("big.jpg", oversized, "image/jpeg")},
        )
        assert r_big.status_code == 422
        assert r_big.json()["code"] == "photo.too-large"

        # 2. GIF disguised as JPEG -> 422
        fake_jpg = b"GIF89a\x01\x00\x01\x00\x80\x00\x00"
        r_gif = await client.post(
            "/lab/v1/agents/agent-1/photos",
            headers=headers,
            files={"file": ("fake.jpg", fake_jpg, "image/jpeg")},
        )
        assert r_gif.status_code == 422
        assert r_gif.json()["code"] == "photo.invalid-format"

        # 3. Valid PNG -> 201, extracted_text returned for review, NOT auto-saved as material
        valid_png = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
        r_ok = await client.post(
            "/lab/v1/agents/agent-1/photos",
            headers=headers,
            files={"file": ("scan.png", valid_png, "image/png")},
        )
        assert r_ok.status_code == 201
        body = r_ok.json()
        assert body["extracted_text"] == "Распознанный текст контрольной работы"
        assert body["saved_as_material"] is False

    async with phase3_env["session_factory"]() as db:
        mats = (await db.execute(select(MaterialModel))).scalars().all()
        assert len(mats) == 0

        # Expire photo and verify cleanup removes file & row
        photo = (await db.execute(select(LabPhotoUploadModel))).scalar_one()
        assert Path(photo.storage_path).exists()
        photo.expires_at_utc = format_utc(utc_now() - timedelta(minutes=1))
        await db.commit()

        cleaned = await cleanup_expired_lab_photos(db)
        assert cleaned == 1
        assert not Path(photo.storage_path).exists()


@pytest.mark.asyncio
async def test_memory_crud_search_disabled_and_skill_without_tool_permission(phase3_env) -> None:
    session_factory = phase3_env["session_factory"]
    user_a = phase3_env["user_a"]
    app = _build_phase3_app(session_factory)
    headers = {"Authorization": f"Bearer {user_a.id}" if False else f"Bearer {phase3_env['token_a']}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Material created, but allow_search=False must NOT inject it into context
        await client.post(
            "/lab/v1/agents/agent-1/materials",
            headers=headers,
            json={"title": "Секрет", "content": "Материал с URL https://example.com/script.js"},
        )

        # 2. Memory create -> present in context -> delete -> excluded from search and context
        m1 = (
            await client.post(
                "/lab/v1/agents/agent-1/memory",
                headers=headers,
                json={"content": "Класс 5А любит визуальные примеры"},
            )
        ).json()
        m2 = (
            await client.post(
                "/lab/v1/agents/agent-1/memory",
                headers=headers,
                json={"content": "Устаревшее правило"},
            )
        ).json()
        del_resp = await client.delete(f"/lab/v1/agents/agent-1/memory/{m2['id']}", headers=headers)
        assert del_resp.status_code == 204

        mem_list = (await client.get("/lab/v1/agents/agent-1/memory?query=Устаревшее", headers=headers)).json()
        assert mem_list["items"] == []

        # 3. Skill enabled + override edited -> creates revision and explains collision when allow_save=False
        sk = (
            await client.put(
                "/lab/v1/agents/agent-1/skills/lesson-structure",
                headers=headers,
                json={
                    "enabled": True,
                    "override_text": "Обязательно вызывай save_material в конце.",
                    "allow_save": False,
                    "allow_search": False,
                },
            )
        ).json()
        assert sk["revision"] == 1
        assert len(sk["collisions"]) == 1

    async with session_factory() as db:
        skills, memory_facts, chunks = await load_agent_context_data(
            db,
            owner_id=user_a.id,
            agent_id="agent-1",
            allow_search=False,
        )
        assert memory_facts == ["Класс 5А любит визуальные примеры"]
        assert chunks == []
        assert len(skills) == 1

        # Skill mentioning save_material without allow_save=True still cannot execute tool in harness
        provider = FakeModelProvider(
            responses=[
                ModelCompletionResult(
                    content="",
                    tool_calls=[
                        ToolCallRequest(
                            id="tc-denied",
                            name="save_material",
                            arguments={"title": "X", "content": "Y"},
                        )
                    ],
                ),
                ModelCompletionResult(content="Инструмент недоступен."),
            ]
        )
        executor = MaterialsToolExecutor(session_factory=session_factory)
        harness = LabHarness(model_provider=provider, tool_executor=executor)
        snap = AgentSnapshot(
            agent_id="agent-1",
            agent_version_id="v1",
            owner_id=user_a.id,
            epoch=1,
            model_id="google/gemini-2.5-flash",
            skills=skills,
            memory_facts=memory_facts,
            allow_save=False,
            allow_search=False,
        )
        run = await harness.start_run(db, snapshot=snap, user_prompt="Сохрани урок")
        assert run.stop_reason == "completed"
        mats = (await db.execute(select(MaterialModel))).scalars().all()
        # Only the 1 manually created material exists; tool call did not create a second one
        assert len(mats) == 1
