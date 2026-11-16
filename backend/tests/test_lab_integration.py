from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient

from app.core.database import SessionLocal
from app.main import app
from app.modules.lab.harness import LabHarness
from app.modules.lab.model_provider import ModelCompletionResult, ToolCallRequest
from app.modules.lab.runs_router import _build_runtime_models_catalog, _lookup_agent_epoch, get_harness
from app.modules.mcp import MaterialsToolExecutor


class FakeProvider:
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


async def _login_dev(client: AsyncClient) -> dict[str, str]:
    resp = await client.post(
        "/mobile/auth/login",
        json={"email": "local-dev@craft-ai.local", "password": "LocalDevPass123!"},
    )
    assert resp.status_code == 200
    return {"Authorization": f"Bearer {resp.json()['accessToken']}"}


@pytest.mark.asyncio
async def test_phase1_phase2_phase3_end_to_end_on_real_app(client: AsyncClient, monkeypatch) -> None:
    monkeypatch.setattr("app.modules.lab.catalog.settings.lab_model_1_id", "google/gemini-2.5-flash")
    monkeypatch.setattr("app.modules.lab.catalog.settings.lab_model_1_supports_tools", True)
    monkeypatch.setattr("app.modules.lab.catalog.settings.lab_model_1_supports_vision", True)

    headers = await _login_dev(client)

    models_resp = await client.get("/lab/v1/models", headers=headers)
    assert models_resp.status_code == 200
    available_models = [m for m in models_resp.json()["models"] if m["available"]]
    assert available_models, "At least one lab model must be configured in settings"
    model_id = available_models[0]["model_id"]

    # 1. Create agent via Phase 1 API
    agent_resp = await client.post(
        "/lab/v1/agents",
        headers=headers,
        json={
            "name": "Интеграционный агент",
            "task_type": "prepare_tasks",
            "subject": "Физика",
            "grade": "8",
            "model_id": model_id,
            "instruction": "Помогай готовить задания.",
            "skills": [{"skill_id": "prepare_tasks", "version": 1}],
            "permissions": {"save_material": True, "search_materials": True},
        },
    )
    assert agent_resp.status_code == 201
    agent_id = agent_resp.json()["id"]

    # 2. Add memory entry via Phase 3 API
    mem_resp = await client.post(
        f"/lab/v1/agents/{agent_id}/memory",
        headers=headers,
        json={"content": "Класс 8Б любит задачи с графиками"},
    )
    assert mem_resp.status_code == 201

    provider = FakeProvider(
        responses=[
            ModelCompletionResult(
                content="",
                tool_calls=[
                    ToolCallRequest(
                        id="tc-1",
                        name="save_material",
                        arguments={"title": "Тест по физике", "content": "Задача 1: найдите силу тока."},
                    )
                ],
            ),
            ModelCompletionResult(content="Тест сохранён."),
            ModelCompletionResult(
                content="",
                tool_calls=[
                    ToolCallRequest(
                        id="tc-2",
                        name="search_materials",
                        arguments={"query": "физике"},
                    )
                ],
            ),
            ModelCompletionResult(content="Нашёл тест по физике."),
        ]
    )
    harness = LabHarness(
        model_provider=provider,
        tool_executor=MaterialsToolExecutor(session_factory=SessionLocal),
        models_catalog=_build_runtime_models_catalog(),
        epoch_lookup=_lookup_agent_epoch,
    )
    app.dependency_overrides[get_harness] = lambda: harness
    try:
        # 3. Start run -> awaits confirmation for save_material
        run1 = (
            await client.post(
                f"/lab/v1/agents/{agent_id}/runs",
                headers={**headers, "Idempotency-Key": "e2e-run-1"},
                json={"prompt": "Составь и сохрани тест"},
            )
        ).json()
        assert run1["status"] == "awaiting_confirmation"
        # Verify Phase 3 memory was assembled into context
        assert "Класс 8Б любит задачи с графиками" in provider.calls[0]["messages"][0]["content"]

        action_id = run1["pending_actions"][0]["id"]
        approved = (
            await client.post(
                f"/lab/v1/runs/{run1['id']}/actions/{action_id}",
                headers=headers,
                json={"decision": "approve"},
            )
        ).json()
        assert approved["status"] == "completed"

        # Material appears in Phase 3 materials list
        mats = (await client.get(f"/lab/v1/agents/{agent_id}/materials", headers=headers)).json()
        assert len(mats["items"]) == 1
        material_id = mats["items"][0]["id"]

        # 4. Second run searches and finds saved material
        run2 = (
            await client.post(
                f"/lab/v1/agents/{agent_id}/runs",
                headers={**headers, "Idempotency-Key": "e2e-run-2"},
                json={"prompt": "Найди сохранённый тест"},
            )
        ).json()
        assert run2["status"] == "completed"
        tool_evts = [e for e in run2["events"] if e["event_type"] == "tool_result"]
        assert tool_evts[0]["payload"]["result"]["items"][0]["material_id"] == material_id

        # 5. Reset agent via Phase 1 clears materials & memory and increments epoch
        reset_resp = await client.post(f"/lab/v1/agents/{agent_id}/reset", headers=headers)
        assert reset_resp.status_code == 200
        assert reset_resp.json()["epoch"] == 1

        mats_after = (await client.get(f"/lab/v1/agents/{agent_id}/materials", headers=headers)).json()
        mem_after = (await client.get(f"/lab/v1/agents/{agent_id}/memory", headers=headers)).json()
        assert mats_after["items"] == []
        assert mem_after["items"] == []
    finally:
        app.dependency_overrides.pop(get_harness, None)
