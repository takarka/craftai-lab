import asyncio
import os
import subprocess
import sys

import pytest
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from pydantic import ValidationError
from sqlalchemy import func, inspect, select, text
from sqlalchemy.ext.asyncio import create_async_engine

from app.core.config import Settings, normalize_database_url, settings
from app.core.database import Base, engine
from app.core.migrations import adopt_legacy_schema, initialize_database
from app.main import app, lifespan
from app.manage import fingerprint, transfer_database, verify_copy


def test_production_requires_postgres_and_accepts_provider_urls():
    config = Settings(_env_file=None, app_env="production", database_url="postgres://user:password@host/craftai")
    assert config.database_url == "postgresql+asyncpg://user:password@host/craftai"
    assert normalize_database_url("postgresql://u:p@host/db?sslmode=require").endswith("?ssl=require")
    with pytest.raises(ValidationError, match="ephemeral SQLite is disabled"):
        Settings(_env_file=None, app_env="production", database_url="sqlite+aiosqlite:///lost.db")
    with pytest.raises(ValidationError) as error:
        Settings(_env_file=None, database_url="mysql://user:private-password@host/db")
    assert "private-password" not in str(error.value)


async def test_frozen_migration_matches_current_models():
    async with engine.connect() as connection:
        differences = await connection.run_sync(
            lambda c: compare_metadata(MigrationContext.configure(c, opts={"compare_type": True}), Base.metadata)
        )
        assert differences == []
        assert await connection.scalar(text("SELECT version_num FROM alembic_version")) == "0001_initial"
    await initialize_database(engine)


async def seed_sample(database):
    tables = Base.metadata.tables
    async with database.begin() as connection:
        await connection.execute(tables["users"].insert(), {
            "id": "persistent-owner", "email": "persistent@example.invalid", "name": "Учитель",
            "password_hash": "synthetic-hash", "terms_revision": "test", "privacy_revision": "test",
            "created_at_utc": "2026-11-19T00:00:00Z",
        })
        await connection.execute(tables["lab_agents"].insert(), {
            "id": "persistent-agent", "owner_id": "persistent-owner", "slot": 1, "name": "Физика",
        })
        await connection.execute(tables["lab_agent_versions"].insert(), {
            "id": "persistent-version", "agent_id": "persistent-agent", "version": 1,
            "configuration": {"instruction": "Три задания", "permissions": {"save_material": True}},
        })
        await connection.execute(tables["lab_materials"].insert(), {
            "id": "persistent-material", "owner_id": "persistent-owner", "agent_id": "persistent-agent",
            "title": "Испарение", "text": "Переход жидкости в газ.",
        })
        await connection.execute(tables["lab_memory_entries"].insert(), {
            "id": "persistent-memory", "owner_id": "persistent-owner", "agent_id": "persistent-agent",
            "text": "Пятый класс",
        })
        await connection.execute(tables["lab_course_progress"].insert(), {
            "owner_id": "persistent-owner", "completed_lessons": [1, 2], "current_lesson": 3,
        })
        await connection.execute(tables["idempotency_records"].insert(), {
            "id": 41, "user_id": "persistent-owner", "route": "/test", "idempotency_key": "original",
            "request_hash": "hash", "status_code": 200, "response_json": {"ok": True},
            "created_at_utc": "2026-11-19T00:00:00Z", "expires_at_utc": "2099-01-01T00:00:00Z",
        })


async def test_explicit_legacy_adoption_preserves_rows_and_rejects_wrong_schema(tmp_path):
    legacy = create_async_engine(f"sqlite+aiosqlite:///{tmp_path / 'legacy.db'}")
    try:
        async with legacy.begin() as connection:
            await connection.run_sync(Base.metadata.create_all)
        await seed_sample(legacy)
        with pytest.raises(RuntimeError, match="Unversioned database"):
            await initialize_database(legacy)
        async with legacy.begin() as connection:
            await connection.run_sync(adopt_legacy_schema)
        await initialize_database(legacy)
        async with legacy.connect() as connection:
            assert await connection.scalar(select(func.count()).select_from(Base.metadata.tables["lab_materials"])) == 1
    finally:
        await legacy.dispose()
    broken = create_async_engine(f"sqlite+aiosqlite:///{tmp_path / 'broken.db'}")
    try:
        async with broken.begin() as connection:
            await connection.execute(text("CREATE TABLE users (id TEXT PRIMARY KEY)"))
        with pytest.raises(RuntimeError, match="differs from baseline"):
            async with broken.begin() as connection:
                await connection.run_sync(adopt_legacy_schema)
        async with broken.connect() as connection:
            assert "alembic_version" not in await connection.run_sync(lambda c: inspect(c).get_table_names())
    finally:
        await broken.dispose()


async def test_sqlite_import_preserves_every_row_resets_sequence_and_refuses_overwrite(tmp_path):
    source = create_async_engine(f"sqlite+aiosqlite:///{tmp_path / 'source.db'}")
    try:
        await initialize_database(source)
        await seed_sample(source)
        # The global fixture is restricted to a test_* database.
        async with engine.begin() as connection:
            for table in reversed(Base.metadata.sorted_tables):
                await connection.execute(table.delete())
        counts = await transfer_database(source, engine)
        assert counts["users"] == counts["lab_materials"] == counts["lab_memory_entries"] == 1
        await engine.dispose()
        await initialize_database(engine)
        await verify_copy(source, engine)
        async with engine.connect() as connection:
            before = await fingerprint(connection)
        with pytest.raises(RuntimeError, match="empty target"):
            await transfer_database(source, engine)
        async with engine.connect() as connection:
            assert await fingerprint(connection) == before
        table = Base.metadata.tables["idempotency_records"]
        async with engine.begin() as connection:
            row = (await connection.execute(select(table))).mappings().one()
            values = {key: value for key, value in row.items() if key != "id"}
            values["idempotency_key"] = "after-import"
            inserted = await connection.execute(table.insert().values(**values).returning(table.c.id))
            assert inserted.scalar_one() == 42
    finally:
        await source.dispose()


async def test_api_state_survives_new_migration_process_and_startup(client, tmp_path, monkeypatch):
    login = await client.post("/mobile/auth/login", json={
        "email": "local-dev@craft-ai.local", "password": "LocalDevPass123!",
    })
    assert login.status_code == 200
    headers = {"Authorization": f"Bearer {login.json()['accessToken']}"}
    response = await client.post("/lab/v1/agents", headers=headers, json={
        "name": "Учитель после перезапуска", "instruction": "Три вопроса без ответов",
    })
    assert response.status_code == 201
    agent = response.json()
    await client.put("/lab/v1/course/progress", headers=headers, json={"completed_lessons": [1], "current_lesson": 2})
    async with engine.connect() as connection:
        before = await fingerprint(connection)
    storage = tmp_path / "persistent-storage"
    storage.mkdir()
    marker = storage / "synthetic-material.txt"
    marker.write_text("Учебный текст")
    monkeypatch.setattr(settings, "storage_dir", str(storage))
    await engine.dispose()
    process = await asyncio.to_thread(
        subprocess.run, [sys.executable, "-m", "app.manage", "migrate"],
        env=os.environ.copy(), capture_output=True, text=True, timeout=30,
    )
    assert process.returncode == 0, process.stderr
    async with lifespan(app):
        restored = await client.get(f"/lab/v1/agents/{agent['id']}", headers=headers)
        assert restored.json() == agent
        progress = await client.get("/lab/v1/course/progress", headers=headers)
        assert progress.json()["completed_lessons"] == [1]
        assert marker.read_text() == "Учебный текст"
        async with engine.connect() as connection:
            assert await fingerprint(connection) == before
