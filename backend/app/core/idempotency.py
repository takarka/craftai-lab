import hashlib
import json
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import IdempotencyRecordModel
from app.core.errors import ApiError
from app.core.security import format_utc, utc_now


def compute_request_hash(payload: object) -> str:
    serialized = json.dumps(payload, sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.sha256(serialized.encode("utf-8")).hexdigest()


async def check_idempotency(
    db: AsyncSession,
    *,
    user_id: str,
    route: str,
    key: str | None,
    request_hash: str,
) -> tuple[int, dict] | None:
    if not key or not key.strip():
        return None
    clean_key = key.strip()[:100]
    stmt = select(IdempotencyRecordModel).where(
        IdempotencyRecordModel.user_id == user_id,
        IdempotencyRecordModel.route == route,
        IdempotencyRecordModel.idempotency_key == clean_key,
    )
    row = (await db.execute(stmt)).scalar_one_or_none()
    if row is None:
        return None
    if row.expires_at_utc < format_utc(utc_now()):
        await db.delete(row)
        await db.commit()
        return None
    if row.request_hash != request_hash:
        raise ApiError(
            status_code=409,
            code="idempotency.key-reused",
            message="Ключ идемпотентности уже использован с другими параметрами запроса.",
        )
    return row.status_code, row.response_json


async def save_idempotency(
    db: AsyncSession,
    *,
    user_id: str,
    route: str,
    key: str | None,
    request_hash: str,
    status_code: int,
    response_json: dict,
) -> None:
    if not key or not key.strip():
        return
    now = utc_now()
    record = IdempotencyRecordModel(
        user_id=user_id,
        route=route,
        idempotency_key=key.strip()[:100],
        request_hash=request_hash,
        status_code=status_code,
        response_json=response_json,
        created_at_utc=format_utc(now),
        expires_at_utc=format_utc(now + timedelta(hours=24)),
    )
    db.add(record)
    await db.commit()
