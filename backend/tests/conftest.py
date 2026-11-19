import os
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.engine import make_url

test_url = os.environ.get("CRAFTAI_TEST_DATABASE_URL", "sqlite+aiosqlite:///./test_craftai.db")
if not Path(make_url(test_url).database or "").name.startswith("test_"):
    raise RuntimeError("Tests recreate their database. CRAFTAI_TEST_DATABASE_URL must name a test_* database.")
os.environ["CRAFTAI_DATABASE_URL"] = test_url
os.environ["CRAFTAI_APP_ENV"] = "test"
os.environ["CRAFTAI_JWT_SECRET"] = "test-only-signing-key-at-least-32-bytes"
os.environ["CRAFTAI_STORAGE_DIR"] = "./test_storage"
os.environ["CRAFTAI_ENABLE_EMBEDDED_WORKER"] = "false"

from app.core.database import Base, SessionLocal, engine
from app.main import app, seed_default_dev_user
from app.core.migrations import upgrade_schema
from app.modules.lab.catalog import seed_catalog


@pytest.fixture(autouse=True)
async def setup_database():
    Path("./test_storage").mkdir(parents=True, exist_ok=True)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.execute(text("DROP TABLE IF EXISTS alembic_version"))
        await conn.run_sync(upgrade_schema)
    await seed_default_dev_user()
    async with SessionLocal() as db:
        await seed_catalog(db)
        await db.commit()
    yield
    await engine.dispose()


@pytest.fixture
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as ac:
        yield ac
