"""Database operations. URLs are read from environment variables, never CLI arguments."""

import argparse
import asyncio
import hashlib
import json
import os

from sqlalchemy import Integer, func, select, text
from sqlalchemy.ext.asyncio import create_async_engine

from app.core.config import normalize_database_url, settings
from app.core.migrations import (
    adopt_legacy_schema,
    application_metadata,
    assert_legacy_schema,
    initialize_database,
)


def database_engine(url):
    return create_async_engine(normalize_database_url(url), pool_pre_ping=True)


async def fingerprint(connection):
    """Compare complete rows without exposing their contents in logs."""
    result = {}
    for table in application_metadata().sorted_tables:
        rows = (await connection.execute(select(table))).mappings().all()
        encoded = sorted(json.dumps(dict(row), ensure_ascii=False, sort_keys=True, separators=(",", ":")) for row in rows)
        digest = hashlib.sha256()
        for row in encoded:
            raw = row.encode("utf-8")
            digest.update(len(raw).to_bytes(8, "big"))
            digest.update(raw)
        result[table.name] = {"rows": len(rows), "sha256": digest.hexdigest()}
    return result


async def transfer_database(source_engine, target_engine):
    """Copy a stopped application's database into an empty, migrated target."""
    if source_engine.url == target_engine.url:
        raise RuntimeError("Source and target databases must be different.")
    await initialize_database(target_engine)
    metadata = application_metadata()
    async with source_engine.connect() as source, target_engine.begin() as target:
        await source.run_sync(assert_legacy_schema)
        await target.run_sync(assert_legacy_schema)
        for table in metadata.sorted_tables:
            if await target.scalar(select(func.count()).select_from(table)):
                raise RuntimeError("Import requires an empty target database; existing rows were not modified.")
        for table in metadata.sorted_tables:
            stream = await source.stream(select(table))
            async for batch in stream.mappings().partitions(500):
                await target.execute(table.insert(), [dict(row) for row in batch])
        if target.dialect.name == "postgresql":
            quote = target.dialect.identifier_preparer.quote
            for table in metadata.sorted_tables:
                keys = list(table.primary_key.columns)
                if len(keys) != 1 or not isinstance(keys[0].type, Integer) or keys[0].foreign_keys:
                    continue
                column = keys[0]
                await target.execute(
                    text(
                        "SELECT setval(pg_get_serial_sequence(:table, :column), "
                        f"COALESCE(MAX({quote(column.name)}), 1), MAX({quote(column.name)}) IS NOT NULL) "
                        f"FROM {quote(table.name)}"
                    ),
                    {"table": table.name, "column": column.name},
                )
        before, after = await fingerprint(source), await fingerprint(target)
        if before != after:
            raise RuntimeError("Import verification failed; the target transaction was rolled back.")
        return {name: value["rows"] for name, value in after.items()}


async def verify_copy(source_engine, target_engine):
    async with source_engine.connect() as source, target_engine.connect() as target:
        await source.run_sync(assert_legacy_schema)
        await target.run_sync(assert_legacy_schema)
        if await fingerprint(source) != await fingerprint(target):
            raise RuntimeError("Database contents differ.")


async def run(operation):
    engine = database_engine(settings.database_url)
    try:
        if operation == "migrate":
            await initialize_database(engine)
        elif operation == "adopt-legacy":
            async with engine.begin() as connection:
                await connection.run_sync(adopt_legacy_schema)
        else:
            source_url = os.environ.get("CRAFTAI_IMPORT_SOURCE_URL")
            if not source_url:
                raise RuntimeError("Set CRAFTAI_IMPORT_SOURCE_URL to the source database URL.")
            source = database_engine(source_url)
            try:
                if operation == "import":
                    counts = await transfer_database(source, engine)
                    print(json.dumps({"imported_rows": counts}, sort_keys=True))
                else:
                    await verify_copy(source, engine)
            finally:
                await source.dispose()
    finally:
        await engine.dispose()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["migrate", "adopt-legacy", "import", "verify-copy"])
    args = parser.parse_args()
    try:
        asyncio.run(run(args.operation))
    except (ValueError, RuntimeError) as exc:
        parser.exit(1, f"{exc}\n")
    except Exception:
        parser.exit(1, "Database operation failed. Check connectivity, permissions and schema compatibility.\n")
    print("Database operation completed.")


if __name__ == "__main__":
    main()
