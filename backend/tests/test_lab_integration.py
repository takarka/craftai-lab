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


@pytest.mark.parametrize("configured_slot", [None, 1, 2])
async def test_draft_agent_run_uses_configured_slot_or_reports_server_configuration(
    client: AsyncClient, monkeypatch, configured_slot: int | None,
) -> None:
    for slot in (1, 2):
        monkeypatch.setattr(
            f"app.modules.lab.catalog.settings.lab_model_{slot}_id",
            "test/configured-model" if slot == configured_slot else "",
        )
    headers = await _login_dev(client)
    created = await client.post("/lab/v1/agents", headers=headers, json={"name": "Черновик"})
    assert created.status_code == 201
    agent = created.json()
    provider = FakeProvider([ModelCompletionResult(content="Готово.")])
    harness = LabHarness(
        model_provider=provider,
        tool_executor=MaterialsToolExecutor(session_factory=SessionLocal),
        models_catalog=_build_runtime_models_catalog(),
        epoch_lookup=_lookup_agent_epoch,
    )
    app.dependency_overrides[get_harness] = lambda: harness
    try:
        response = await client.post(
            f"/lab/v1/agents/{agent['id']}/runs",
            headers={**headers, "Idempotency-Key": "draft-model-configuration"},
            json={"prompt": "Объясни закон Ома"},
        )
        if configured_slot is None:
            assert response.status_code == 503
            assert response.json()["code"] == "model.not-configured"
            assert response.json()["type"] == "Failure"
            assert provider.calls == []
        else:
            assert response.status_code == 201, response.text
            assert response.json()["status"] == "completed"
            assert provider.calls[0]["model_id"] == "test/configured-model"
    finally:
        app.dependency_overrides.pop(get_harness, None)


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


async def test_dialogue_reload_retry_and_agent_isolation(client: AsyncClient, monkeypatch) -> None:
    monkeypatch.setattr("app.modules.lab.catalog.settings.lab_model_1_id", "google/gemini-2.5-flash")
    headers = await _login_dev(client)
    agents = []
    for name in ("Один", "Два"):
        result = await client.post("/lab/v1/agents", headers=headers, json={"name": name})
        assert result.status_code == 201
        agents.append(result.json()["id"])
    a = f"/lab/v1/agents/{agents[0]}"
    b = f"/lab/v1/agents/{agents[1]}"
    provider = FakeProvider([ModelCompletionResult(content="Понял: 5 класс, ровно три пункта.")])
    harness = LabHarness(model_provider=provider, epoch_lookup=_lookup_agent_epoch)
    app.dependency_overrides[get_harness] = lambda: harness
    try:
        initial = (await client.get(f"{a}/dialogue", headers=headers)).json()
        assert initial["turns"] == []
        first_body = {
            "prompt": "Пятый класс. Давай ровно три пункта.",
            "dialogue": True,
            "conversation_id": initial["conversation_id"],
        }
        first_headers = {**headers, "Idempotency-Key": "dialogue-first"}
        one = await client.post(f"{a}/runs", headers=first_headers, json=first_body)
        assert one.status_code == 201, one.text
        repeated = await client.post(f"{a}/runs", headers=first_headers, json=first_body)
        assert repeated.json()["id"] == one.json()["id"]
        mismatch = await client.post(
            f"{a}/runs", headers=first_headers, json={**first_body, "prompt": "Другой запрос"},
        )
        assert mismatch.status_code == 409
        assert len(provider.calls) == 1

        reopened = (await client.get(f"{a}/dialogue", headers=headers)).json()
        assert reopened["conversation_id"] == initial["conversation_id"]
        assert [turn["prompt"] for turn in reopened["turns"]] == [first_body["prompt"]]
        assert reopened["turns"][0]["run"]["final_output"] == "Понял: 5 класс, ровно три пункта."
        b_reopened = (await client.get(f"{b}/dialogue", headers=headers)).json()
        assert b_reopened["conversation_id"] != initial["conversation_id"]
        assert b_reopened["turns"] == []
        rejected = await client.post(f"{b}/runs", headers=first_headers, json=first_body)
        assert rejected.status_code == 409

        two = await client.post(
            f"{a}/runs", headers={**headers, "Idempotency-Key": "dialogue-follow-up"},
            json={**first_body, "prompt": "А теперь про испарение."},
        )
        assert two.status_code == 201, two.text
        assert [message["role"] for message in provider.calls[1]["messages"]][-3:] == [
            "user", "assistant", "user",
        ]
        assert provider.calls[1]["messages"][-3]["content"] == first_body["prompt"]
        assert "5 класс, ровно три пункта" in provider.calls[1]["messages"][-2]["content"]

        latest = (await client.get(f"{a}/dialogue?limit=1", headers=headers)).json()
        assert latest["turns"][0]["run"]["id"] == two.json()["id"]
        previous = (await client.get(
            f"{a}/dialogue?limit=1&before={latest['next_before']}", headers=headers,
        )).json()
        assert previous["turns"][0]["run"]["id"] == one.json()["id"]
        assert previous["next_before"] is None
        wrong_cursor = await client.get(f"{b}/dialogue?before={one.json()['id']}", headers=headers)
        assert wrong_cursor.status_code == 404
    finally:
        app.dependency_overrides.pop(get_harness, None)
