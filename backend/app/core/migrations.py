"""Run Alembic on the existing async connection, including during startup."""

from pathlib import Path

from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import inspect, text


def application_metadata():
    from app.core.database import Base
    # Register all tables without importing the HTTP application or its lifespan.
    from app.modules.lab import materials_models, models, runtime_models  # noqa: F401

    return Base.metadata


def migration_config(connection):
    config = Config()
    config.set_main_option("script_location", str(Path(__file__).resolve().parents[1] / "migrations"))
    config.attributes["connection"] = connection
    return config


def lock_schema(connection):
    if connection.dialect.name == "postgresql":
        # A transaction-scoped lock serializes startup across API processes.
        connection.execute(text("SELECT pg_advisory_xact_lock(1947111901)"))


def upgrade_schema(connection):
    lock_schema(connection)
    tables = set(inspect(connection).get_table_names())
    if tables and "alembic_version" not in tables:
        raise RuntimeError(
            "Unversioned database detected. Back it up and run python -m app.manage adopt-legacy before starting the API."
        )
    command.upgrade(migration_config(connection), "head")


def assert_legacy_schema(connection):
    from app.migrations.schema_v1 import metadata

    differences = compare_metadata(MigrationContext.configure(connection, opts={"compare_type": True}), metadata)
    if differences:
        # Do not log row data, database URLs, or credentials.
        raise RuntimeError("Legacy schema differs from baseline; automatic adoption/import refused.")
    inspector = inspect(connection)
    for table in metadata.tables.values():
        expected = {c.name for c in table.constraints if c.__class__.__name__ == "CheckConstraint"}
        actual = {c["name"] for c in inspector.get_check_constraints(table.name)}
        if expected != actual:
            raise RuntimeError("Legacy check constraints differ from baseline; adoption/import refused.")


def adopt_legacy_schema(connection):
    lock_schema(connection)
    if "alembic_version" in inspect(connection).get_table_names():
        raise RuntimeError("Database is already versioned; use the migrate command.")
    assert_legacy_schema(connection)
    command.stamp(migration_config(connection), "0001_initial")


async def initialize_database(engine):
    async with engine.begin() as connection:
        await connection.run_sync(upgrade_schema)
