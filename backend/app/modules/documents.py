import hashlib
import io
import os
import re
import uuid
import zipfile
from datetime import timedelta
from pathlib import Path
from typing import Any

from docx import Document as DocxDocument
from fastapi import APIRouter, Depends, File, Form, Header, Response, UploadFile
from fastapi.responses import JSONResponse
from pypdf import PdfReader
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import AttachmentModel, get_db
from app.core.errors import ApiError
from app.core.idempotency import check_idempotency, compute_request_hash, save_idempotency
from app.core.security import CurrentUser, format_utc, get_current_user, utc_now

router = APIRouter()

MAX_DOCUMENT_BYTES = 10 * 1024 * 1024  # 10 MiB
MAX_DOCX_UNPACKED_BYTES = 50 * 1024 * 1024  # 50 MiB
MAX_PDF_PAGES = 50
MAX_EXTRACTED_CHARS = 200_000

DOCX_MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
PDF_MIME = "application/pdf"
TXT_MIME = "text/plain"


def _safe_filename(name: str) -> str:
    base = re.split(r"[\\/]", name or "document")[-1]
    cleaned = "".join(ch for ch in base if ord(ch) >= 0x20 and ord(ch) != 0x7F).strip()
    if not cleaned:
        return "document.txt"
    return cleaned[:255]


def _inspect_and_extract(file_name: str, raw_bytes: bytes) -> tuple[str, str | None, str | None]:
    """Returns (mime_type, extracted_text, reject_reason)."""
    ext = file_name.rsplit(".", 1)[-1].lower() if "." in file_name else ""

    # 1. PDF inspection
    if raw_bytes.startswith(b"%PDF-") or ext == "pdf":
        if not raw_bytes.startswith(b"%PDF-"):
            return PDF_MIME, None, "file.corrupt"
        try:
            reader = PdfReader(io.BytesIO(raw_bytes))
            if reader.is_encrypted:
                return PDF_MIME, None, "file.encrypted"
            num_pages = len(reader.pages)
            if num_pages == 0:
                return PDF_MIME, None, "file.corrupt"
            if num_pages > MAX_PDF_PAGES:
                return PDF_MIME, None, "file.limits-exceeded"

            pages_with_text = 0
            chunks: list[str] = []
            for page in reader.pages:
                txt = (page.extract_text() or "").strip()
                if len(txt) >= 10:
                    pages_with_text += 1
                    chunks.append(txt)

            if pages_with_text == 0:
                return PDF_MIME, None, "file.no-text-layer"
            if pages_with_text / num_pages < 0.8:
                return PDF_MIME, None, "file.partial-text"

            full_text = "\n\n".join(chunks)
            if len(full_text) > MAX_EXTRACTED_CHARS:
                return PDF_MIME, None, "file.limits-exceeded"
            return PDF_MIME, full_text, None
        except Exception:
            return PDF_MIME, None, "file.corrupt"

    # 2. DOCX inspection
    if raw_bytes.startswith(b"PK\x03\x04") or ext == "docx":
        if not raw_bytes.startswith(b"PK\x03\x04"):
            return DOCX_MIME, None, "file.corrupt"
        try:
            with zipfile.ZipFile(io.BytesIO(raw_bytes)) as zf:
                names = zf.namelist()
                if "EncryptedPackage" in names or "EncryptionInfo" in names:
                    return DOCX_MIME, None, "file.encrypted"
                if "word/document.xml" not in names:
                    return DOCX_MIME, None, "file.corrupt"
                total_unpacked = sum(info.file_size for info in zf.infolist())
                if total_unpacked > MAX_DOCX_UNPACKED_BYTES:
                    return DOCX_MIME, None, "file.limits-exceeded"
                if len(raw_bytes) > 0 and (total_unpacked / len(raw_bytes)) > 100:
                    return DOCX_MIME, None, "file.limits-exceeded"

            doc = DocxDocument(io.BytesIO(raw_bytes))
            paragraphs = [p.text.strip() for p in doc.paragraphs if p.text and p.text.strip()]
            for table in doc.tables:
                for row in table.rows:
                    cells = [c.text.strip() for c in row.cells if c.text and c.text.strip()]
                    if cells:
                        paragraphs.append(" | ".join(cells))
            full_text = "\n\n".join(paragraphs)
            if not full_text.strip():
                return DOCX_MIME, None, "file.no-text-layer"
            if len(full_text) > MAX_EXTRACTED_CHARS:
                return DOCX_MIME, None, "file.limits-exceeded"
            return DOCX_MIME, full_text, None
        except Exception:
            return DOCX_MIME, None, "file.corrupt"

    # 3. TXT inspection
    if ext == "txt":
        if b"\x00" in raw_bytes[:1024]:
            return TXT_MIME, None, "file.corrupt"
        try:
            full_text = raw_bytes.decode("utf-8").strip()
        except UnicodeDecodeError:
            return TXT_MIME, None, "file.corrupt"
        if not full_text:
            return TXT_MIME, None, "file.corrupt"
        if len(full_text) > MAX_EXTRACTED_CHARS:
            return TXT_MIME, None, "file.limits-exceeded"
        return TXT_MIME, full_text, None

    raise ApiError(
        status_code=415,
        code="file.unsupported-type",
        message="Поддерживаются только файлы TXT, DOCX и текстовый PDF.",
    )


def _serialize_attachment(row: AttachmentModel) -> dict[str, Any]:
    out: dict[str, Any] = {
        "id": row.id,
        "fileName": row.file_name,
        "mimeType": row.mime_type,
        "sizeBytes": row.size_bytes,
        "status": row.status,
        "createdAtUtc": row.created_at_utc,
        "expiresAtUtc": row.expires_at_utc,
    }
    if row.reject_reason:
        out["rejectReason"] = row.reject_reason
    return out


@router.post("/builder/attachments", status_code=201)
async def upload_attachment(
    file: UploadFile = File(...),
    consentRevision: str = Form(default=""),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> JSONResponse:
    if not consentRevision or not consentRevision.strip():
        raise ApiError(
            status_code=409,
            code="consent.required",
            message="Требуется подтверждение согласия на обработку файла.",
        )

    raw_bytes = await file.read()
    size = len(raw_bytes)
    if size <= 0:
        raise ApiError(status_code=422, code="file.corrupt", message="Файл пуст.")
    if size > MAX_DOCUMENT_BYTES:
        raise ApiError(status_code=413, code="file.too-large", message="Размер файла превышает 10 МиБ.")

    safe_name = _safe_filename(file.filename or "document.txt")
    req_hash = hashlib.sha256(raw_bytes + safe_name.encode("utf-8") + consentRevision.encode("utf-8")).hexdigest()

    cached = await check_idempotency(
        db,
        user_id=current_user.user_id,
        route="POST:/builder/attachments",
        key=idempotency_key,
        request_hash=req_hash,
    )
    if cached is not None:
        return JSONResponse(status_code=cached[0], content=cached[1])

    mime_type, extracted_text, reject_reason = _inspect_and_extract(safe_name, raw_bytes)

    now = utc_now()
    att_id = str(uuid.uuid4())
    status = "rejected" if reject_reason else "uploaded"
    storage_path_str: str | None = None

    if status == "uploaded":
        user_dir = Path(settings.storage_dir) / current_user.user_id / "attachments"
        user_dir.mkdir(parents=True, exist_ok=True)
        dest = user_dir / f"{att_id}_{safe_name}"
        dest.write_bytes(raw_bytes)
        storage_path_str = str(dest)

    att = AttachmentModel(
        id=att_id,
        user_id=current_user.user_id,
        file_name=safe_name,
        mime_type=mime_type,
        size_bytes=size,
        status=status,
        reject_reason=reject_reason,
        consent_revision=consentRevision.strip(),
        storage_path=storage_path_str,
        extracted_text=extracted_text,
        created_at_utc=format_utc(now),
        expires_at_utc=format_utc(now + timedelta(hours=1)),
    )
    db.add(att)
    await db.commit()

    payload = _serialize_attachment(att)
    await save_idempotency(
        db,
        user_id=current_user.user_id,
        route="POST:/builder/attachments",
        key=idempotency_key,
        request_hash=req_hash,
        status_code=201,
        response_json=payload,
    )
    return JSONResponse(status_code=201, content=payload)


@router.get("/builder/attachments/{attachment_id}")
async def get_attachment(
    attachment_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    att = (
        await db.execute(
            select(AttachmentModel).where(
                AttachmentModel.id == attachment_id,
                AttachmentModel.user_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if att is None:
        raise ApiError(status_code=404, code="attachment.not-found", message="Вложение не найдено.")
    return _serialize_attachment(att)


@router.delete("/builder/attachments/{attachment_id}", status_code=204)
async def delete_attachment(
    attachment_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    att = (
        await db.execute(
            select(AttachmentModel).where(
                AttachmentModel.id == attachment_id,
                AttachmentModel.user_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if att is None:
        raise ApiError(status_code=404, code="attachment.not-found", message="Вложение не найдено.")

    if att.storage_path and os.path.isfile(att.storage_path):
        try:
            os.remove(att.storage_path)
        except OSError:
            pass

    await db.delete(att)
    await db.commit()
    return Response(status_code=204)


