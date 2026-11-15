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
async def test_models_chat_sse_and_search(client: AsyncClient):
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

    search_res = await client.post(
        "/builder/search",
        headers=headers,
        json={"query": "методика преподавания дробей", "count": 3},
    )
    assert search_res.status_code == 200
    s_body = search_res.json()
    assert len(s_body["results"]) >= 1
    assert s_body["results"][0]["url"].startswith("https://")


@pytest.mark.asyncio
async def test_calendar_crud_etag_and_recurrence(client: AsyncClient):
    tokens = await _login_dev(client)
    headers = {"Authorization": f"Bearer {tokens['accessToken']}"}

    create_res = await client.post(
        "/builder/calendar/events",
        headers={**headers, "Idempotency-Key": "cal-create-1"},
        json={
            "title": "Планерка кафедры",
            "start": "2026-04-20T09:00:00",
            "end": "2026-04-20T10:00:00",
            "timeZone": "Asia/Almaty",
            "allDay": False,
            "recurrence": {"frequency": "daily", "interval": 1, "count": 3},
        },
    )
    assert create_res.status_code == 201
    event = create_res.json()
    event_id = event["id"]
    assert event["version"] == 1

    range_res = await client.get(
        "/builder/calendar/events",
        headers=headers,
        params={
            "from": "2026-04-20",
            "to": "2026-04-25",
        },
    )
    assert range_res.status_code == 200
    occurrences = range_res.json()["items"]
    assert len(occurrences) == 3

    conflict_res = await client.put(
        f"/builder/calendar/events/{event_id}",
        headers={**headers, "If-Match": '"99"'},
        json={
            "title": "Конфликт",
            "start": "2026-04-20T09:00:00",
            "end": "2026-04-20T10:00:00",
            "timeZone": "Asia/Almaty",
            "allDay": False,
        },
    )
    assert conflict_res.status_code == 412
    assert conflict_res.json()["code"] == "calendar.version-conflict"

    occ_res = await client.put(
        f"/builder/calendar/events/{event_id}/occurrences/2026-04-21",
        headers=headers,
        json={"canceled": True},
    )
    assert occ_res.status_code == 200

    range_after = await client.get(
        "/builder/calendar/events",
        headers=headers,
        params={
            "from": "2026-04-20",
            "to": "2026-04-25",
        },
    )
    assert len(range_after.json()["items"]) == 2

    changes_res = await client.get("/builder/calendar/changes", headers=headers)
    assert changes_res.status_code == 200
    changes_body = changes_res.json()
    assert len(changes_body["items"]) >= 1
    assert "nextCursor" in changes_body


@pytest.mark.asyncio
async def test_documents_pipeline_and_range_download(client: AsyncClient):
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

    job_res = await client.post(
        "/builder/document-jobs",
        headers={**headers, "Idempotency-Key": "job-create-1"},
        json={
            "attachmentId": att["id"],
            "skill": "lesson-plan",
            "parameters": {"topic": "Алгоритмы", "grade": 8, "language": "ru"},
            "outputs": ["docx", "pdf"],
        },
    )
    assert job_res.status_code == 202
    job_id = job_res.json()["id"]

    status_res = await client.get(f"/builder/document-jobs/{job_id}", headers=headers)
    assert status_res.status_code == 200
    job_body = status_res.json()
    assert job_body["status"] == "succeeded"
    assert len(job_body["artifacts"]) == 2

    pdf_art = next(a for a in job_body["artifacts"] if a["format"] == "pdf")
    full_dl = await client.get(f"/builder/artifacts/{pdf_art['id']}/content", headers=headers)
    assert full_dl.status_code == 200
    assert full_dl.content.startswith(b"%PDF-")

    partial_dl = await client.get(
        f"/builder/artifacts/{pdf_art['id']}/content",
        headers={**headers, "Range": "bytes=10-"},
    )
    assert partial_dl.status_code == 206
    assert partial_dl.content == full_dl.content[10:]


@pytest.mark.asyncio
async def test_schedules_and_mcp(client: AsyncClient):
    tokens = await _login_dev(client)
    headers = {"Authorization": f"Bearer {tokens['accessToken']}"}

    sched_res = await client.put(
        "/builder/schedules/daily-brief",
        headers=headers,
        json={
            "enabled": True,
            "timeZone": "Asia/Almaty",
            "timing": {"frequency": "daily", "localTime": "07:30"},
            "parameters": {"includeCalendar": True},
            "extraContext": "Учитывать уроки первой смены",
            "consentRevision": "schedules-2026-10-v1",
        },
    )
    assert sched_res.status_code == 200
    sched = sched_res.json()
    assert "extraContext" in sched
    sched_id = sched["id"]

    run_res = await client.post(
        f"/builder/schedules/{sched_id}/run-now",
        headers={**headers, "Idempotency-Key": "run-now-1"},
    )
    assert run_res.status_code == 202
    run_id = run_res.json()["id"]

    detail_res = await client.get(f"/builder/runs/{run_id}", headers=headers)
    assert detail_res.status_code == 200
    detail = detail_res.json()
    assert detail["status"] == "succeeded"
    assert detail["result"]["format"] == "structured"

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
