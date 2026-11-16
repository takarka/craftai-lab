from __future__ import annotations

import base64
import contextlib
import uuid
from datetime import timedelta
from pathlib import Path
from typing import Protocol

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import ApiError
from app.core.security import format_utc, utc_now
from app.modules.lab.materials_models import LabPhotoUploadModel
from app.modules.lab.model_provider import OpenRouterModelProvider

MAX_PHOTO_BYTES = 10 * 1024 * 1024  # 10 MiB
PHOTO_TTL_HOURS = 24

_JPEG_MAGIC = b"\xff\xd8\xff"
_PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def detect_allowed_image_mime(raw_bytes: bytes) -> str:
    """Validate image strictly by magic bytes (JPEG/PNG only)."""
    if raw_bytes.startswith(_JPEG_MAGIC):
        return "image/jpeg"
    if raw_bytes.startswith(_PNG_MAGIC):
        return "image/png"
    raise ApiError(
        status_code=422,
        code="photo.invalid-format",
        message="Поддерживаются только изображения JPEG и PNG (проверка по сигнатуре файла).",
    )


class PhotoTextExtractor(Protocol):
    async def extract_text(self, *, raw_bytes: bytes, mime_type: str) -> str: ...


class VisionModelPhotoTextExtractor:
    """Extracts text from a photo using a vision-capable model on the Lab server."""

    def __init__(self, vision_model_id: str = "google/gemini-2.5-flash") -> None:
        self._vision_model_id = vision_model_id
        self._provider = OpenRouterModelProvider()

    async def extract_text(self, *, raw_bytes: bytes, mime_type: str) -> str:
        b64 = base64.b64encode(raw_bytes).decode("ascii")
        data_uri = f"data:{mime_type};base64,{b64}"
        result = await self._provider.complete(
            model_id=self._vision_model_id,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": (
                                "Извлеки весь читаемый текст с изображения дословно, без комментариев "
                                "и без добавления отсутствующих фрагментов."
                            ),
                        },
                        {"type": "image_url", "image_url": {"url": data_uri}},
                    ],
                }
            ],
        )
        return result.content.strip()


async def store_and_extract_photo(
    db: AsyncSession,
    *,
    owner_id: str,
    agent_id: str,
    file_name: str,
    raw_bytes: bytes,
    extractor: PhotoTextExtractor,
    storage_dir: str | None = None,
) -> LabPhotoUploadModel:
    if not raw_bytes:
        raise ApiError(status_code=422, code="photo.empty", message="Файл изображения пуст.")
    if len(raw_bytes) > MAX_PHOTO_BYTES:
        raise ApiError(
            status_code=422,
            code="photo.too-large",
            message="Размер изображения превышает допустимый лимит 10 МБ.",
        )

    mime_type = detect_allowed_image_mime(raw_bytes)
    extracted_text = await extractor.extract_text(raw_bytes=raw_bytes, mime_type=mime_type)

    base_dir = Path(storage_dir or settings.storage_dir) / "lab_photos"
    base_dir.mkdir(parents=True, exist_ok=True)
    photo_id = str(uuid.uuid4())
    ext = ".jpg" if mime_type == "image/jpeg" else ".png"
    target_path = base_dir / f"{photo_id}{ext}"
    target_path.write_bytes(raw_bytes)

    now = utc_now()
    row = LabPhotoUploadModel(
        id=photo_id,
        owner_id=owner_id,
        agent_id=agent_id,
        file_name=(file_name or f"photo{ext}")[:255],
        mime_type=mime_type,
        size_bytes=len(raw_bytes),
        storage_path=str(target_path),
        extracted_text=extracted_text,
        created_at_utc=format_utc(now),
        expires_at_utc=format_utc(now + timedelta(hours=PHOTO_TTL_HOURS)),
    )
    db.add(row)
    await db.commit()
    return row


async def cleanup_expired_lab_photos(db: AsyncSession) -> int:
    now_str = format_utc(utc_now())
    rows = (
        await db.execute(
            select(LabPhotoUploadModel).where(LabPhotoUploadModel.expires_at_utc <= now_str)
        )
    ).scalars().all()
    deleted = 0
    for row in rows:
        with contextlib.suppress(OSError):
            Path(row.storage_path).unlink(missing_ok=True)
        await db.delete(row)
        deleted += 1
    if deleted:
        await db.commit()
    return deleted
