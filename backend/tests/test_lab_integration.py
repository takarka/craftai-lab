from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient

from app.core.database import SessionLocal
from app.main import app
from app.modules.lab.harness import LabHarness
from app.modules.lab.model_provider import ModelCompletionResult, ModelDescriptor, ToolCallRequest
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


@pytest.mark.parametrize("compaction_succeeds", [True, False])
async def test_dialogue_compacts_old_turns_without_erasing_history(
    client: AsyncClient, monkeypatch, compaction_succeeds: bool,
) -> None:
    model_id = "google/gemini-2.5-flash"
    monkeypatch.setattr("app.modules.lab.catalog.settings.lab_model_1_id", model_id)
    headers = await _login_dev(client)
    response = await client.post("/lab/v1/agents", headers=headers, json={"name": "Учебный диалог"})
    assert response.status_code == 201
    route = f"/lab/v1/agents/{response.json()['id']}"
    first_prompt = "Пятый класс. Ровно три пункта. " + "материал " * 110
    recent_prompt = "ВТОРАЯ РЕПЛИКА " + "пример " * 140
    latest_prompt = "ТРЕТЬЯ РЕПЛИКА " + "карточка " * 110
    next_prompt = "НОВЫЙ ЗАПРОС " + "урок " * 185
    latest_answer = "ПРОВЕРЕННЫЙ ОТВЕТ " + "деталь " * 140
    summary = "Пятый класс. Ровно три пункта."
    provider = FakeProvider([
        ModelCompletionResult(content="Запомнил формат."),
        ModelCompletionResult(content="Пример готов. " + "текст " * 175),
        ModelCompletionResult(content=latest_answer),
        ModelCompletionResult(content=summary if compaction_succeeds else "", finish_reason=(
            "stop" if compaction_succeeds else "length"
        )),
        ModelCompletionResult(content="Три пункта для пятого класса."),
    ])
    harness = LabHarness(
        model_provider=provider, epoch_lookup=_lookup_agent_epoch,
        models_catalog={model_id: ModelDescriptor(model_id, "Test", True, False, context_window=3000)},
    )
    app.dependency_overrides[get_harness] = lambda: harness
    try:
        async def read_dialogue():
            result = await client.get(f"{route}/dialogue", headers=headers)
            assert result.status_code == 200, result.text
            return result.json()

        initial = await read_dialogue()
        for index, prompt in enumerate((first_prompt, recent_prompt, latest_prompt)):
            posted = await client.post(
                f"{route}/runs", headers={**headers, "Idempotency-Key": f"compact-{index}"},
                json={"prompt": prompt, "dialogue": True, "conversation_id": initial["conversation_id"]},
            )
            assert posted.status_code == 201, posted.text
            assert posted.json()["status"] == "completed", posted.text
        assert len(provider.calls) == 3
        reopened = await read_dialogue()
        followup = await client.post(
            f"{route}/runs", headers={**headers, "Idempotency-Key": "compact-new"},
            json={"prompt": next_prompt, "dialogue": True, "conversation_id": reopened["conversation_id"]},
        )
        assert followup.status_code == 201, followup.text
        assert provider.calls[3]["tools"] is None
        assert "earlier_turns" in provider.calls[3]["messages"][1]["content"]
        assert first_prompt in provider.calls[3]["messages"][1]["content"]
        if compaction_succeeds:
            assert followup.json()["status"] == "completed", followup.text
            contents = [message["content"] for message in provider.calls[4]["messages"]]
            assert any(summary in content for content in contents)
            assert first_prompt not in contents
            assert latest_prompt in contents
            assert latest_answer in contents
            assert next_prompt == contents[-1]
        else:
            assert followup.json()["status"] == "failed"
            assert followup.json()["error_code"] == "dialogue.compaction-failed"
            assert len(provider.calls) == 4

        after = await read_dialogue()
        assert [turn["prompt"] for turn in after["turns"]] == [
            first_prompt, recent_prompt, latest_prompt, next_prompt,
        ]
        assert after["turns"][0]["run"]["final_output"] == "Запомнил формат."
        if compaction_succeeds:
            followup_body = {"prompt": "Ещё один пример?", "dialogue": True, "conversation_id": after["conversation_id"]}
            next_result = await client.post(
                f"{route}/runs", headers={**headers, "Idempotency-Key": "compact-reuse"}, json=followup_body,
            )
            assert next_result.json()["status"] == "completed", next_result.text
            assert len(provider.calls) == 6
            reused = [message["content"] for message in provider.calls[-1]["messages"]]
            assert any(summary in content for content in reused)
            assert first_prompt not in reused
            assert latest_prompt in reused
    finally:
        app.dependency_overrides.pop(get_harness, None)
