from __future__ import annotations

import pytest
from httpx import AsyncClient


async def _login_dev(client: AsyncClient) -> dict[str, str]:
    res = await client.post(
        "/mobile/auth/login",
        json={"email": "local-dev@craft-ai.local", "password": "LocalDevPass123!"},
    )
    assert res.status_code == 200
    body = res.json()
    assert "accessToken" in body
    assert "refreshToken" in body
    return body


@pytest.mark.asyncio
async def test_auth_lifecycle_and_usage(client: AsyncClient):
    docs_res = await client.get("/mobile/auth/documents")
    assert docs_res.status_code == 200
    docs = docs_res.json()
    assert docs["termsRevision"] == "2026.1-ru"
    assert docs["privacyRevision"] == "2026.1-ru"

    weak_res = await client.post(
        "/mobile/auth/register",
        json={
            "name": "Test User",
            "email": "weak@craft-ai.local",
            "password": "short",
            "termsRevision": "2026.1-ru",
            "privacyRevision": "2026.1-ru",
            "language": "ru",
        },
    )
    assert weak_res.status_code == 400
    assert weak_res.json()["code"] == "AUTH_WEAK_PASSWORD"

    reg_res = await client.post(
        "/mobile/auth/register",
        json={
            "name": "Алия Сарсенова",
            "email": "aliya@craft-ai.local",
            "password": "StrongPassword123",
            "termsRevision": "2026.1-ru",
            "privacyRevision": "2026.1-ru",
            "language": "ru",
        },
    )
    assert reg_res.status_code == 200
    tokens = reg_res.json()
    headers = {"Authorization": f"Bearer {tokens['accessToken']}"}

    usage_res = await client.get("/me/usage", headers=headers)
    assert usage_res.status_code == 200
    usage = usage_res.json()
    assert usage["status"] == "available"
    assert "totalTokens" in usage["tokens"]

    ref_res = await client.post(
        "/mobile/auth/refresh",
        json={"refreshToken": tokens["refreshToken"]},
    )
    assert ref_res.status_code == 200
    new_tokens = ref_res.json()
    assert new_tokens["refreshToken"] != tokens["refreshToken"]


@pytest.mark.asyncio
async def test_models_chat_sse(client: AsyncClient):
    tokens = await _login_dev(client)
    headers = {"Authorization": f"Bearer {tokens['accessToken']}"}

    mod_res = await client.get("/builder/models", headers=headers)
    assert mod_res.status_code == 200
    cat = mod_res.json()
    models_by_cat = {m["category"]: m["modelId"] for m in cat["models"]}
    assert "gemini" in models_by_cat["fast"]
    assert "qwen" in models_by_cat["standard"]
    assert "deepseek" in models_by_cat["advanced"]

    chat_res = await client.post(
        "/builder/chat/completions",
        headers=headers,
        json={
            "category": "fast",
            "messages": [{"role": "user", "content": "Привет! Сделай план урока на 45 минут."}],
        },
    )
    assert chat_res.status_code == 200
    assert "text/event-stream" in chat_res.headers["content-type"]
    event_types = []
    for block in chat_res.text.split("\n\n"):
        for line in block.splitlines():
            if line.startswith("event: "):
                event_types.append(line[7:].strip())
    assert "start" in event_types
    assert "text_delta" in event_types
    assert "usage" in event_types
    assert event_types[-1] == "terminal"


@pytest.mark.asyncio
async def test_attachments_upload_and_delete(client: AsyncClient):
    tokens = await _login_dev(client)
    headers = {"Authorization": f"Bearer {tokens['accessToken']}"}

    raw_bytes = (
        "План урока по информатике: алгоритмы и структуры данных.\n"
        "Цели урока: изучить линейные и разветвляющиеся алгоритмы, циклы и списки."
    ).encode("utf-8")

    att_res = await client.post(
        "/builder/attachments",
        headers={**headers, "Idempotency-Key": "att-upload-1"},
        files={"file": ("lesson_notes.txt", raw_bytes, "text/plain")},
        data={"consentRevision": "files-2026-10-v1"},
    )
    assert att_res.status_code == 201
    att = att_res.json()
    assert att["status"] == "uploaded"

    del_res = await client.delete(f"/builder/attachments/{att['id']}", headers=headers)
    assert del_res.status_code == 204


@pytest.mark.asyncio
async def test_mcp_tools(client: AsyncClient):
    tokens = await _login_dev(client)
    headers = {"Authorization": f"Bearer {tokens['accessToken']}"}

    mcp_list = await client.post(
        "/mcp/v1",
        headers=headers,
        json={"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}},
    )
    assert mcp_list.status_code == 200
    tools = mcp_list.json()["result"]["tools"]
    names = {t["name"] for t in tools}
    assert {"save_material", "search_materials"}.issubset(names)

    agent = await client.post("/lab/v1/agents", headers=headers, json={"name": "MCP contract agent"})
    assert agent.status_code == 201
    agent_id = agent.json()["id"]

    save_call = await client.post(
        "/mcp/v1",
        headers={**headers, "X-Agent-Id": agent_id},
        json={
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {
                "name": "save_material",
                "arguments": {"title": "Дроби", "content": "Сложение дробей с общим знаменателем"},
            },
        },
    )
    assert save_call.status_code == 200
    material_id = save_call.json()["result"]["material_id"]
    assert material_id

    search_call = await client.post(
        "/mcp/v1",
        headers={**headers, "X-Agent-Id": agent_id},
        json={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "search_materials", "arguments": {"query": "дроби"}},
        },
    )
    assert search_call.status_code == 200
    items = search_call.json()["result"]["items"]
    assert any(item["material_id"] == material_id for item in items)


@pytest.mark.parametrize("tool", ["save_material", "search_materials"])
async def test_mcp_rejects_missing_foreign_and_deleted_agents(client: AsyncClient, tool):
    tokens = await _login_dev(client)
    owner = {"Authorization": f"Bearer {tokens['accessToken']}"}
    registered = await client.post("/mobile/auth/register", json={
        "name": "Other teacher", "email": "mcp-other@craft-ai.local", "password": "StrongPassword123",
        "termsRevision": "2026.1-ru", "privacyRevision": "2026.1-ru", "language": "ru",
    })
    assert registered.status_code == 200
    foreign = {"Authorization": f"Bearer {registered.json()['accessToken']}"}
    created = await client.post("/lab/v1/agents", headers=owner, json={"name": "Owned agent"})
    assert created.status_code == 201
    agent_id = created.json()["id"]
    payload = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {
        "name": tool, "arguments": {"title": "Тема", "content": "Учебный текст", "query": "Тема"},
    }}
    for headers, candidate in [(owner, "missing-agent"), (foreign, agent_id)]:
        response = await client.post("/mcp/v1", headers={**headers, "X-Agent-Id": candidate}, json=payload)
        assert response.status_code == 404
        assert response.json()["code"] == "agents.not-found"
    materials = await client.get(f"/lab/v1/agents/{agent_id}/materials", headers=owner)
    assert materials.json()["items"] == []
    assert (await client.delete(f"/lab/v1/agents/{agent_id}", headers=owner)).status_code == 204
    deleted = await client.post("/mcp/v1", headers={**owner, "X-Agent-Id": agent_id}, json=payload)
    assert deleted.status_code == 404
