from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.database import Base, UserModel, get_db
from app.core.errors import register_exception_handlers
from app.core.security import create_access_token, format_utc, hash_password, utc_now
from app.modules.lab.context_assembler import HistoryMessage, LabContextAssembler, SkillContextItem
from app.modules.lab.harness import AgentSnapshot, LabHarness
from app.modules.lab.model_provider import ModelCompletionResult, ModelDescriptor, ToolCallRequest
from app.modules.lab.runs_router import get_harness, get_snapshot_resolver, router as runs_router
from app.modules.lab.runtime_models import LabPendingActionModel, LabRunEventModel, LabRunModel, LabUsageLedgerModel


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
            return ModelCompletionResult(content="Готово.", input_tokens=10, output_tokens=5)
        return self._responses.pop(0)


class RecordingToolExecutor:
    def __init__(self) -> None:
        self.executed: list[dict[str, Any]] = []

    async def execute(
        self,
        *,
        owner_id: str,
        agent_id: str,
        tool_name: str,
        params: dict[str, Any],
    ) -> dict[str, Any]:
        self.executed.append(
            {
                "owner_id": owner_id,
                "agent_id": agent_id,
                "tool_name": tool_name,
                "params": params,
            }
        )
        if tool_name == "save_material":
            return {"status": "saved", "material_id": "mat-123", "title": params.get("title", "")}
        if tool_name == "search_materials":
            return {"status": "ok", "items": [{"material_id": "mat-1", "title": "Дроби"}]}
        return {"status": "ok"}


@pytest.fixture
async def lab_test_env():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", future=True)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)

    user_a = UserModel(
        id=str(uuid.uuid4()),
        email="teacher-a@example.com",
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
        email="teacher-b@example.com",
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
        await db.commit()

    token_a, _ = create_access_token(
        user_id=user_a.id,
        email=user_a.email,
        name=user_a.name,
        role=user_a.role,
    )
    token_b, _ = create_access_token(
        user_id=user_b.id,
        email=user_b.email,
        name=user_b.name,
        role=user_b.role,
    )

    yield {
        "engine": engine,
        "session_factory": session_factory,
        "user_a": user_a,
        "user_b": user_b,
        "token_a": token_a,
        "token_b": token_b,
    }

    await engine.dispose()


def _build_test_app(
    session_factory: async_sessionmaker[AsyncSession],
    harness: LabHarness,
    snapshot: AgentSnapshot,
) -> FastAPI:
    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(runs_router)

    async def override_get_db():
        async with session_factory() as db:
            yield db

    async def override_snapshot_resolver(*, db: AsyncSession, owner_id: str, agent_id: str) -> AgentSnapshot:
        return snapshot

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_harness] = lambda: harness
    app.dependency_overrides[get_snapshot_resolver] = lambda: override_snapshot_resolver
    return app


def test_context_assembler_order_and_budget() -> None:
    assembler = LabContextAssembler(default_reserved_tokens=50)
    assembled = assembler.assemble(
        user_prompt="Составь тест",
        context_window=250,
        platform_rules="Платформа: строго по фактам.",
        instruction="Ты учитель математики.",
        skills=[SkillContextItem(slug="quiz", title="Тесты", content="Делай 3 варианта.", override_text="Для 5 класса.")],
        knowledge_chunks=["Дроби: числитель и знаменатель."],
        memory_facts=["Ученики путают знаменатели."],
        conversation_history=[
            HistoryMessage(role="user", content="Очень старое сообщение " * 30),
            HistoryMessage(role="assistant", content="Недавний ответ"),
        ],
    )
    sys_msg = assembled.messages[0]["content"]
    assert sys_msg.index("Правила платформы:") < sys_msg.index("Инструкция агента:")
    assert sys_msg.index("Инструкция агента:") < sys_msg.index("Включённые скиллы:")
    assert sys_msg.index("Включённые скиллы:") < sys_msg.index("Фрагменты материалов:")
    assert sys_msg.index("Фрагменты материалов:") < sys_msg.index("Факты памяти:")
    assert assembled.included_history_count == 1
    assert assembled.messages[-1] == {"role": "user", "content": "Составь тест"}


@pytest.mark.asyncio
async def test_fourth_tool_call_stops_with_tool_limit(lab_test_env) -> None:
    user_a = lab_test_env["user_a"]
    provider = FakeModelProvider(
        responses=[
            ModelCompletionResult(
                content="",
                tool_calls=[
                    ToolCallRequest(id="c1", name="search_materials", arguments={"query": "q1"}),
                    ToolCallRequest(id="c2", name="search_materials", arguments={"query": "q2"}),
                    ToolCallRequest(id="c3", name="search_materials", arguments={"query": "q3"}),
                    ToolCallRequest(id="c4", name="search_materials", arguments={"query": "q4"}),
                ],
                input_tokens=50,
                output_tokens=20,
            )
        ]
    )
    executor = RecordingToolExecutor()
    harness = LabHarness(model_provider=provider, tool_executor=executor)
    snapshot = AgentSnapshot(
        agent_id="agent-1",
        agent_version_id="ver-1",
        owner_id=user_a.id,
        epoch=1,
        model_id="google/gemini-2.5-flash",
        allow_search=True,
    )
    app = _build_test_app(lab_test_env["session_factory"], harness, snapshot)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.post(
            "/lab/v1/agents/agent-1/runs",
            headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
            json={"prompt": "Найди материалы"},
        )
    assert resp.status_code == 201
    body = resp.json()
    assert body["status"] == "completed"
    assert body["stop_reason"] == "tool_limit"
    assert body["tool_calls_count"] == 3
    assert len(executor.executed) == 3


@pytest.mark.asyncio
async def test_idempotency_key_returns_same_run_and_rejects_mismatch(lab_test_env) -> None:
    user_a = lab_test_env["user_a"]
    provider = FakeModelProvider(
        responses=[
            ModelCompletionResult(content="Ответ 1", input_tokens=20, output_tokens=10),
            ModelCompletionResult(content="Ответ 2", input_tokens=20, output_tokens=10),
        ]
    )
    harness = LabHarness(model_provider=provider)
    snapshot = AgentSnapshot(
        agent_id="agent-1",
        agent_version_id="ver-1",
        owner_id=user_a.id,
        epoch=1,
        model_id="google/gemini-2.5-flash",
    )
    app = _build_test_app(lab_test_env["session_factory"], harness, snapshot)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r1 = await client.post(
            "/lab/v1/agents/agent-1/runs",
            headers={"Authorization": f"Bearer {lab_test_env['token_a']}", "Idempotency-Key": "k-123"},
            json={"prompt": "Привет"},
        )
        r2 = await client.post(
            "/lab/v1/agents/agent-1/runs",
            headers={"Authorization": f"Bearer {lab_test_env['token_a']}", "Idempotency-Key": "k-123"},
            json={"prompt": "Привет"},
        )
        r3 = await client.post(
            "/lab/v1/agents/agent-1/runs",
            headers={"Authorization": f"Bearer {lab_test_env['token_a']}", "Idempotency-Key": "k-123"},
            json={"prompt": "Другой запрос"},
        )

    assert r1.status_code == 201
    assert r2.status_code == 201
    assert r1.json()["id"] == r2.json()["id"]
    assert len(provider.calls) == 1
    assert r3.status_code == 409
    assert r3.json()["code"] == "idempotency.key-reused"


@pytest.mark.asyncio
async def test_confirmation_deny_creates_no_record_and_approve_executes(lab_test_env) -> None:
    user_a = lab_test_env["user_a"]
    provider = FakeModelProvider(
        responses=[
            ModelCompletionResult(
                content="",
                tool_calls=[
                    ToolCallRequest(
                        id="save-1",
                        name="save_material",
                        arguments={"title": "Тест", "content": "Вопросы"},
                    )
                ],
            ),
            ModelCompletionResult(
                content="",
                tool_calls=[
                    ToolCallRequest(
                        id="save-2",
                        name="save_material",
                        arguments={"title": "Тест 2", "content": "Вопросы 2"},
                    )
                ],
            ),
            ModelCompletionResult(content="Материал сохранён (mat-123)."),
        ]
    )
    executor = RecordingToolExecutor()
    harness = LabHarness(model_provider=provider, tool_executor=executor)
    snapshot = AgentSnapshot(
        agent_id="agent-1",
        agent_version_id="ver-1",
        owner_id=user_a.id,
        epoch=1,
        model_id="google/gemini-2.5-flash",
        allow_save=True,
    )
    app = _build_test_app(lab_test_env["session_factory"], harness, snapshot)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Run 1: deny
        run1 = (
            await client.post(
                "/lab/v1/agents/agent-1/runs",
                headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
                json={"prompt": "Сохрани тест"},
            )
        ).json()
        assert run1["status"] == "awaiting_confirmation"
        action1_id = run1["pending_actions"][0]["id"]

        denied = (
            await client.post(
                f"/lab/v1/runs/{run1['id']}/actions/{action1_id}",
                headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
                json={"decision": "deny"},
            )
        ).json()
        assert denied["status"] == "completed"
        assert denied["stop_reason"] == "action_denied"
        assert len(executor.executed) == 0

        # Run 2: changed params rejected, then matching approve executes
        run2 = (
            await client.post(
                "/lab/v1/agents/agent-1/runs",
                headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
                json={"prompt": "Сохрани тест 2"},
            )
        ).json()
        action2_id = run2["pending_actions"][0]["id"]

        mismatch = await client.post(
            f"/lab/v1/runs/{run2['id']}/actions/{action2_id}",
            headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
            json={"decision": "approve", "params": {"title": "Изменено", "content": "Вопросы 2"}},
        )
        assert mismatch.status_code == 409
        assert mismatch.json()["code"] == "action.params-changed"
        assert len(executor.executed) == 0

        approved = (
            await client.post(
                f"/lab/v1/runs/{run2['id']}/actions/{action2_id}",
                headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
                json={"decision": "approve"},
            )
        ).json()
        assert approved["status"] == "completed"
        assert approved["stop_reason"] == "completed"
        assert len(executor.executed) == 1
        assert executor.executed[0]["tool_name"] == "save_material"


@pytest.mark.asyncio
async def test_expired_pending_action_is_not_executed(lab_test_env) -> None:
    user_a = lab_test_env["user_a"]
    provider = FakeModelProvider(
        responses=[
            ModelCompletionResult(
                content="",
                tool_calls=[
                    ToolCallRequest(
                        id="save-exp",
                        name="save_material",
                        arguments={"title": "Просроченный", "content": "Текст"},
                    )
                ],
            )
        ]
    )
    executor = RecordingToolExecutor()
    harness = LabHarness(model_provider=provider, tool_executor=executor)
    snapshot = AgentSnapshot(
        agent_id="agent-1",
        agent_version_id="ver-1",
        owner_id=user_a.id,
        epoch=1,
        model_id="google/gemini-2.5-flash",
        allow_save=True,
    )
    app = _build_test_app(lab_test_env["session_factory"], harness, snapshot)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        run = (
            await client.post(
                "/lab/v1/agents/agent-1/runs",
                headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
                json={"prompt": "Сохрани"},
            )
        ).json()
        action_id = run["pending_actions"][0]["id"]

        async with lab_test_env["session_factory"]() as db:
            action = (
                await db.execute(select(LabPendingActionModel).where(LabPendingActionModel.id == action_id))
            ).scalar_one()
            action.expires_at_utc = format_utc(utc_now() - timedelta(minutes=1))
            await db.commit()

        resp = await client.post(
            f"/lab/v1/runs/{run['id']}/actions/{action_id}",
            headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
            json={"decision": "approve"},
        )
    assert resp.status_code == 409
    assert resp.json()["code"] == "action.expired"
    assert len(executor.executed) == 0


@pytest.mark.asyncio
async def test_late_events_after_reset_are_discarded(lab_test_env) -> None:
    user_a = lab_test_env["user_a"]
    current_epoch = {"value": 1}

    async def epoch_lookup(_db: AsyncSession, _owner_id: str, _agent_id: str) -> int:
        return current_epoch["value"]

    harness = LabHarness(model_provider=FakeModelProvider([]), epoch_lookup=epoch_lookup)
    async with lab_test_env["session_factory"]() as db:
        run = LabRunModel(
            id=str(uuid.uuid4()),
            owner_id=user_a.id,
            agent_id="agent-1",
            agent_version_id="ver-1",
            epoch=1,
            model_id="google/gemini-2.5-flash",
            version_snapshot_json={},
            status="running",
            user_prompt="Тест",
            created_at_utc=format_utc(utc_now()),
            updated_at_utc=format_utc(utc_now()),
        )
        db.add(run)
        await db.commit()

        # Simulate agent reset incrementing epoch to 2
        current_epoch["value"] = 2
        late_event = await harness.append_event(db, run, "tool_result", {"data": "late"})
        assert late_event is None

        events = (
            await db.execute(select(LabRunEventModel).where(LabRunEventModel.run_id == run.id))
        ).scalars().all()
        assert len(events) == 0


@pytest.mark.asyncio
async def test_owner_isolation_and_sse_sanitization(lab_test_env) -> None:
    user_a = lab_test_env["user_a"]
    provider = FakeModelProvider(responses=[ModelCompletionResult(content="Ответ A")])
    harness = LabHarness(model_provider=provider)
    snapshot = AgentSnapshot(
        agent_id="agent-1",
        agent_version_id="ver-1",
        owner_id=user_a.id,
        epoch=1,
        model_id="google/gemini-2.5-flash",
    )
    app = _build_test_app(lab_test_env["session_factory"], harness, snapshot)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        run = (
            await client.post(
                "/lab/v1/agents/agent-1/runs",
                headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
                json={"prompt": "Привет"},
            )
        ).json()

        # User B gets 404 on run endpoints
        r_get = await client.get(
            f"/lab/v1/runs/{run['id']}",
            headers={"Authorization": f"Bearer {lab_test_env['token_b']}"},
        )
        r_sse = await client.get(
            f"/lab/v1/runs/{run['id']}/stream",
            headers={"Authorization": f"Bearer {lab_test_env['token_b']}"},
        )
        assert r_get.status_code == 404
        assert r_sse.status_code == 404

        # User A can stream SSE with Last-Event-ID
        sse_all = await client.get(
            f"/lab/v1/runs/{run['id']}/stream",
            headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
        )
        assert sse_all.status_code == 200
        assert "id: evt_1" in sse_all.text
        assert "id: evt_2" in sse_all.text

        sse_resume = await client.get(
            f"/lab/v1/runs/{run['id']}/stream",
            headers={"Authorization": f"Bearer {lab_test_env['token_a']}", "Last-Event-ID": "evt_1"},
        )
        assert "id: evt_1" not in sse_resume.text
        assert "id: evt_2" in sse_resume.text

        # Secrets and hidden reasoning stripped from events
        async with lab_test_env["session_factory"]() as db:
            run_row = (await db.execute(select(LabRunModel).where(LabRunModel.id == run["id"]))).scalar_one()
            evt = await harness.append_event(
                db,
                run_row,
                "debug_check",
                {"ok": True, "reasoning": "secret thoughts", "api_key": "sk-123"},
            )
            assert evt is not None
            assert evt.payload_json == {"ok": True}


@pytest.mark.asyncio
async def test_incompatible_model_blocked_and_pilot_budget_enforced(lab_test_env) -> None:
    user_a = lab_test_env["user_a"]
    provider = FakeModelProvider(responses=[ModelCompletionResult(content="ok", input_tokens=100, output_tokens=50)])
    custom_catalog = {
        "text-only": ModelDescriptor(
            model_id="text-only",
            display_name="Text Only",
            supports_tools=False,
            supports_vision=False,
            input_cost_per_1m_usd=1000.0,
            output_cost_per_1m_usd=1000.0,
        )
    }
    harness = LabHarness(model_provider=provider, models_catalog=custom_catalog, pilot_budget_usd=0.01)

    # 1. Tools requested on non-tools model -> 422
    snap_tools = AgentSnapshot(
        agent_id="agent-1",
        agent_version_id="ver-1",
        owner_id=user_a.id,
        epoch=1,
        model_id="text-only",
        allow_save=True,
    )
    app_tools = _build_test_app(lab_test_env["session_factory"], harness, snap_tools)
    async with AsyncClient(transport=ASGITransport(app=app_tools), base_url="http://test") as client:
        r_tools = await client.post(
            "/lab/v1/agents/agent-1/runs",
            headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
            json={"prompt": "Сохрани"},
        )
    assert r_tools.status_code == 422
    assert r_tools.json()["code"] == "model.incompatible-tools"
    assert len(provider.calls) == 0

    # 2. Vision requested on non-vision model -> 422
    snap_plain = AgentSnapshot(
        agent_id="agent-1",
        agent_version_id="ver-1",
        owner_id=user_a.id,
        epoch=1,
        model_id="text-only",
    )
    app_plain = _build_test_app(lab_test_env["session_factory"], harness, snap_plain)
    async with AsyncClient(transport=ASGITransport(app=app_plain), base_url="http://test") as client:
        r_vision = await client.post(
            "/lab/v1/agents/agent-1/runs",
            headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
            json={"prompt": "Что на фото?", "image_data_uris": ["data:image/png;base64,AAAA"]},
        )
        assert r_vision.status_code == 422
        assert r_vision.json()["code"] == "model.incompatible-vision"

        # 3. First valid run consumes > $0.01 budget, second run blocked with 402
        r_ok = await client.post(
            "/lab/v1/agents/agent-1/runs",
            headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
            json={"prompt": "Привет"},
        )
        assert r_ok.status_code == 201

        r_budget = await client.post(
            "/lab/v1/agents/agent-1/runs",
            headers={"Authorization": f"Bearer {lab_test_env['token_a']}"},
            json={"prompt": "Ещё раз"},
        )
        assert r_budget.status_code == 402
        assert r_budget.json()["code"] == "budget.exceeded"

    async with lab_test_env["session_factory"]() as db:
        ledger = (await db.execute(select(LabUsageLedgerModel))).scalars().all()
        assert len(ledger) == 1
        assert ledger[0].total_tokens == 150
