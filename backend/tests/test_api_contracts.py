from __future__ import annotations

import os
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

os.environ["CRAFTAI_DATABASE_URL"] = "sqlite+aiosqlite:///./test_craftai.db"
os.environ["CRAFTAI_STORAGE_DIR"] = "./test_storage"
os.environ["CRAFTAI_ENABLE_EMBEDDED_WORKER"] = "false"

from app.core.database import Base, engine  # noqa: E402
from app.main import app, seed_default_dev_user  # noqa: E402


@pytest.fixture(autouse=True)
async def setup_database():
    Path("./test_storage").mkdir(parents=True, exist_ok=True)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    await seed_default_dev_user()
    yield


@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as ac:
        yield ac


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
    assert any(t["name"] == "search_lessons" for t in tools)

    mcp_call = await client.post(
        "/mcp/v1",
        headers=headers,
        json={
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {"name": "search_lessons", "arguments": {"query": "дроби"}},
        },
    )
    assert mcp_call.status_code == 200
    assert mcp_call.json()["result"]["isError"] is False
