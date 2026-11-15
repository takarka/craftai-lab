import os
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

os.environ["CRAFTAI_DATABASE_URL"] = "sqlite+aiosqlite:///./test_craftai.db"
os.environ["CRAFTAI_STORAGE_DIR"] = "./test_storage"
os.environ["CRAFTAI_ENABLE_EMBEDDED_WORKER"] = "false"

from app.core.database import Base, SessionLocal, engine
from app.main import app, seed_default_dev_user
from app.modules.lab.catalog import seed_catalog


@pytest.fixture(autouse=True)
async def setup_database():
    Path("./test_storage").mkdir(parents=True, exist_ok=True)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
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
