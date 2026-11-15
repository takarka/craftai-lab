import hashlib
import io
import os
import re
import uuid
import zipfile
from datetime import timedelta
from pathlib import Path
from typing import Any
from urllib.parse import quote

from docx import Document as DocxDocument
from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, Header, Request, Response, UploadFile
from fastapi.responses import JSONResponse
from pypdf import PdfReader
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import ArtifactModel, AttachmentModel, DocumentJobModel, SessionLocal, get_db
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

_FONT_REGISTERED = False
_FONT_NAME = "Helvetica"


def _ensure_cyrillic_font() -> str:
    global _FONT_REGISTERED, _FONT_NAME
    if _FONT_REGISTERED:
        return _FONT_NAME

    candidates = [
        Path(__file__).resolve().parents[3] / "Builder" / "assets" / "fonts" / "Onest-400.ttf",
        Path("C:/Windows/Fonts/arial.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
        Path("/usr/share/fonts/noto/NotoSans-Regular.ttf"),
    ]
    for path in candidates:
        if path.is_file():
            try:
                pdfmetrics.registerFont(TTFont("CraftCyrillic", str(path)))
                _FONT_NAME = "CraftCyrillic"
                break
            except Exception:
                continue
    _FONT_REGISTERED = True
    return _FONT_NAME


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


def _serialize_artifact(row: ArtifactModel) -> dict[str, Any]:
    return {
        "id": row.id,
        "jobId": row.job_id,
        "format": row.format,
        "fileName": row.file_name,
        "mimeType": row.mime_type,
        "sizeBytes": row.size_bytes,
        "sha256": row.sha256,
        "expiresAtUtc": row.expires_at_utc,
    }


def _serialize_job(row: DocumentJobModel, artifacts: list[ArtifactModel]) -> dict[str, Any]:
    out: dict[str, Any] = {
        "id": row.id,
        "attachmentId": row.attachment_id,
        "skill": row.skill,
        "status": row.status,
        "artifacts": [_serialize_artifact(a) for a in artifacts],
        "createdAtUtc": row.created_at_utc,
        "updatedAtUtc": row.updated_at_utc,
        "expiresAtUtc": row.expires_at_utc,
    }
    if row.progress is not None:
        out["progress"] = row.progress
    if row.error_json is not None:
        out["error"] = row.error_json
    return out


def _build_structured_document(skill: str, params: dict[str, Any], source_text: str) -> tuple[str, list[tuple[str, str]]]:
    lang = str(params.get("language", "ru"))
    topic = str(params.get("topic") or ("Учебный материал" if lang == "ru" else "Оқу материалы")).strip()
    grade = params.get("grade") or 7
    items_count = int(params.get("itemsCount") or 5)
    excerpt = source_text.strip()[:600].replace("\n", " ")

    if skill == "quiz":
        title = (
            f"Проверочная работа: {topic} ({grade} класс)"
            if lang == "ru"
            else f"Тексеру жұмысы: {topic} ({grade}-сынып)"
        )
        sections: list[tuple[str, str]] = [
            (
                "Основа материала" if lang == "ru" else "Материал негізі",
                f"Краткая выдержка из источника: {excerpt}",
            ),
        ]
        for i in range(1, min(items_count, 15) + 1):
            q_head = f"Вопрос {i}" if lang == "ru" else f"{i}-сұрақ"
            q_body = (
                f"Сформулируйте ключевое правило или решите типовую задачу №{i} по теме «{topic}» на основе изученного материала.\n"
                f"Ключ для учителя: проверено соответствие основному понятию раздела."
                if lang == "ru"
                else f"Оқылған материал негізінде «{topic}» тақырыбы бойынша №{i} негізгі ережені тұжырымдаңыз немесе есепті шығарыңыз.\n"
                f"Мұғалімге арналған кілт: бөлімнің негізгі ұғымына сәйкестігі тексерілді."
            )
            sections.append((q_head, q_body))
        return title, sections

    title = (
        f"План урока: {topic} ({grade} класс)"
        if lang == "ru"
        else f"Сабақ жоспары: {topic} ({grade}-сынып)"
    )
    sections = [
        (
            "1. Учебные цели" if lang == "ru" else "1. Оқу мақсаттары",
            f"Освоить основные понятия по теме «{topic}» и научиться применять их на практике ({grade} класс).",
        ),
        (
            "2. Опорный конспект из документа" if lang == "ru" else "2. Құжаттағы тірек конспект",
            excerpt,
        ),
        (
            "3. Ход занятия (45 минут)" if lang == "ru" else "3. Сабақ барысы (45 минут)",
            "• 0–5 мин: Актуализация знаний и проблемный вопрос.\n"
            "• 5–20 мин: Разбор материала с примерами из загруженного документа.\n"
            "• 20–35 мин: Практическая работа в группах и индивидуально.\n"
            "• 35–45 мин: Формирующее оценивание, рефлексия и домашнее задание.",
        ),
    ]
    return title, sections


def _render_docx_bytes(title: str, sections: list[tuple[str, str]]) -> bytes:
    doc = DocxDocument()
    doc.add_heading(title, level=1)
    for heading, body in sections:
        doc.add_heading(heading, level=2)
        for line in body.split("\n"):
            if line.strip():
                doc.add_paragraph(line.strip())
    buf = io.BytesIO()
    doc.save(buf)
    return buf.getvalue()


def _render_pdf_bytes(title: str, sections: list[tuple[str, str]]) -> bytes:
    font_name = _ensure_cyrillic_font()
    buf = io.BytesIO()
    pdf = SimpleDocTemplate(buf, pagesize=A4, title=title)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "CraftTitle",
        parent=styles["Heading1"],
        fontName=font_name,
        fontSize=16,
        leading=20,
        spaceAfter=12,
    )
    h2_style = ParagraphStyle(
        "CraftH2",
        parent=styles["Heading2"],
        fontName=font_name,
        fontSize=13,
        leading=16,
        spaceBefore=10,
        spaceAfter=6,
    )
    body_style = ParagraphStyle(
        "CraftBody",
        parent=styles["BodyText"],
        fontName=font_name,
        fontSize=11,
        leading=14,
        spaceAfter=6,
    )

    story = [Paragraph(title, title_style), Spacer(1, 8)]
    for heading, body in sections:
        story.append(Paragraph(heading, h2_style))
        for line in body.split("\n"):
            if line.strip():
                safe_line = (
                    line.strip()
                    .replace("&", "&amp;")
                    .replace("<", "&lt;")
                    .replace(">", "&gt;")
                )
                story.append(Paragraph(safe_line, body_style))
    pdf.build(story)
    return buf.getvalue()


async def process_document_job_background(job_id: str) -> None:
    try:
        async with SessionLocal() as db:
            job = (
                await db.execute(select(DocumentJobModel).where(DocumentJobModel.id == job_id))
            ).scalar_one_or_none()
            if job is None or job.status == "canceled":
                return

            att = (
                await db.execute(select(AttachmentModel).where(AttachmentModel.id == job.attachment_id))
            ).scalar_one_or_none()
            if att is None or not att.extracted_text:
                job.status = "failed"
                job.error_json = {
                    "code": "file.no-text-layer",
                    "message": "В документе отсутствует текстовый слой.",
                    "retryable": False,
                }
                job.updated_at_utc = format_utc(utc_now())
                await db.commit()
                return

            job.status = "parsing"
            job.progress = 25
            job.updated_at_utc = format_utc(utc_now())
            await db.commit()

            job.status = "generating"
            job.progress = 60
            job.updated_at_utc = format_utc(utc_now())
            await db.commit()

            title, sections = _build_structured_document(job.skill, job.parameters_json, att.extracted_text)

            await db.refresh(job)
            if job.status == "canceled":
                return

            job.status = "assembling"
            job.progress = 85
            job.updated_at_utc = format_utc(utc_now())
            await db.commit()

            user_dir = Path(settings.storage_dir) / job.user_id / "artifacts"
            user_dir.mkdir(parents=True, exist_ok=True)
            now = utc_now()
            exp_str = format_utc(now + timedelta(hours=24))
            base_stem = Path(att.file_name).stem[:60] or "document"

            for fmt in job.outputs_json:
                art_id = str(uuid.uuid4())
                if fmt == "docx":
                    content_bytes = _render_docx_bytes(title, sections)
                    mime = DOCX_MIME
                    out_name = f"{base_stem}_{job.skill}.docx"
                else:
                    content_bytes = _render_pdf_bytes(title, sections)
                    mime = PDF_MIME
                    out_name = f"{base_stem}_{job.skill}.pdf"

                art_path = user_dir / f"{art_id}.{fmt}"
                art_path.write_bytes(content_bytes)
                digest = hashlib.sha256(content_bytes).hexdigest()

                db.add(
                    ArtifactModel(
                        id=art_id,
                        job_id=job.id,
                        user_id=job.user_id,
                        format=fmt,
                        file_name=out_name,
                        mime_type=mime,
                        size_bytes=len(content_bytes),
                        sha256=digest,
                        storage_path=str(art_path),
                        expires_at_utc=exp_str,
                    )
                )

            # Remove original raw file after successful parse & assembly per EB-00 TTL policy
            if att.storage_path and os.path.isfile(att.storage_path):
                try:
                    os.remove(att.storage_path)
                except OSError:
                    pass

            job.status = "succeeded"
            job.progress = 100
            job.updated_at_utc = format_utc(utc_now())
            await db.commit()
    except Exception:
        async with SessionLocal() as db:
            job = (
                await db.execute(select(DocumentJobModel).where(DocumentJobModel.id == job_id))
            ).scalar_one_or_none()
            if job is not None and job.status not in ("succeeded", "canceled"):
                job.status = "failed"
                job.error_json = {
                    "code": "job.build-failed",
                    "message": "Не удалось собрать итоговый документ.",
                    "retryable": True,
                }
                job.updated_at_utc = format_utc(utc_now())
                await db.commit()


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

    jobs = (
        await db.execute(select(DocumentJobModel).where(DocumentJobModel.attachment_id == att.id))
    ).scalars().all()
    for j in jobs:
        arts = (await db.execute(select(ArtifactModel).where(ArtifactModel.job_id == j.id))).scalars().all()
        for a in arts:
            if os.path.isfile(a.storage_path):
                try:
                    os.remove(a.storage_path)
                except OSError:
                    pass
            await db.delete(a)
        await db.delete(j)

    await db.delete(att)
    await db.commit()
    return Response(status_code=204)


@router.post("/builder/document-jobs", status_code=202)
async def create_document_job(
    body: dict[str, Any],
    background_tasks: BackgroundTasks,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> JSONResponse:
    req_hash = compute_request_hash(body)
    cached = await check_idempotency(
        db,
        user_id=current_user.user_id,
        route="POST:/builder/document-jobs",
        key=idempotency_key,
        request_hash=req_hash,
    )
    if cached is not None:
        return JSONResponse(status_code=cached[0], content=cached[1])

    att_id = str(body.get("attachmentId", ""))
    skill = str(body.get("skill", ""))
    params = body.get("parameters") or {}
    outputs = body.get("outputs") or ["docx", "pdf"]

    if skill not in ("quiz", "lesson-plan"):
        raise ApiError(status_code=400, code="job.invalid-skill", message="Неподдерживаемый навык обработки.")
    if not isinstance(outputs, list) or not outputs or any(o not in ("docx", "pdf") for o in outputs):
        raise ApiError(status_code=400, code="job.invalid-outputs", message="Укажите форматы docx и/или pdf.")

    att = (
        await db.execute(
            select(AttachmentModel).where(
                AttachmentModel.id == att_id,
                AttachmentModel.user_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if att is None:
        raise ApiError(status_code=404, code="attachment.not-found", message="Исходное вложение не найдено.")
    if att.status != "uploaded":
        raise ApiError(
            status_code=422,
            code=att.reject_reason or "file.corrupt",
            message="Вложение было отклонено при проверке.",
        )

    # Check if there's already an active job for this attachment
    active = (
        await db.execute(
            select(DocumentJobModel).where(
                DocumentJobModel.attachment_id == att_id,
                DocumentJobModel.status.in_(["queued", "parsing", "generating", "assembling"]),
            )
        )
    ).scalar_one_or_none()
    if active is not None:
        raise ApiError(
            status_code=409,
            code="job.already-active",
            message="Для этого вложения уже выполняется задание.",
        )

    now = utc_now()
    job = DocumentJobModel(
        id=str(uuid.uuid4()),
        user_id=current_user.user_id,
        attachment_id=att.id,
        skill=skill,
        parameters_json=params,
        outputs_json=outputs,
        status="queued",
        progress=0,
        created_at_utc=format_utc(now),
        updated_at_utc=format_utc(now),
        expires_at_utc=format_utc(now + timedelta(hours=24)),
    )
    db.add(job)
    await db.commit()

    payload = _serialize_job(job, [])
    await save_idempotency(
        db,
        user_id=current_user.user_id,
        route="POST:/builder/document-jobs",
        key=idempotency_key,
        request_hash=req_hash,
        status_code=202,
        response_json=payload,
    )

    background_tasks.add_task(process_document_job_background, job.id)
    return JSONResponse(status_code=202, content=payload)


@router.get("/builder/document-jobs/{job_id}")
async def get_document_job(
    job_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    job = (
        await db.execute(
            select(DocumentJobModel).where(
                DocumentJobModel.id == job_id,
                DocumentJobModel.user_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if job is None:
        raise ApiError(status_code=404, code="job.not-found", message="Задание не найдено.")

    arts = (
        await db.execute(select(ArtifactModel).where(ArtifactModel.job_id == job.id))
    ).scalars().all()
    return _serialize_job(job, list(arts))


@router.post("/builder/document-jobs/{job_id}/cancel", status_code=202)
async def cancel_document_job(
    job_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    job = (
        await db.execute(
            select(DocumentJobModel).where(
                DocumentJobModel.id == job_id,
                DocumentJobModel.user_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if job is None:
        raise ApiError(status_code=404, code="job.not-found", message="Задание не найдено.")

    if job.status not in ("succeeded", "failed", "canceled", "expired"):
        job.status = "canceled"
        job.updated_at_utc = format_utc(utc_now())
        await db.commit()

    arts = (
        await db.execute(select(ArtifactModel).where(ArtifactModel.job_id == job.id))
    ).scalars().all()
    return _serialize_job(job, list(arts))


@router.delete("/builder/document-jobs/{job_id}", status_code=204)
async def delete_document_job(
    job_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    job = (
        await db.execute(
            select(DocumentJobModel).where(
                DocumentJobModel.id == job_id,
                DocumentJobModel.user_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if job is None:
        raise ApiError(status_code=404, code="job.not-found", message="Задание не найдено.")

    arts = (
        await db.execute(select(ArtifactModel).where(ArtifactModel.job_id == job.id))
    ).scalars().all()
    for a in arts:
        if os.path.isfile(a.storage_path):
            try:
                os.remove(a.storage_path)
            except OSError:
                pass
        await db.delete(a)

    await db.delete(job)
    await db.commit()
    return Response(status_code=204)


@router.get("/builder/artifacts/{artifact_id}")
async def get_artifact_meta(
    artifact_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    art = (
        await db.execute(
            select(ArtifactModel).where(
                ArtifactModel.id == artifact_id,
                ArtifactModel.user_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if art is None:
        raise ApiError(status_code=404, code="artifact.not-found", message="Артефакт не найден.")
    if art.expires_at_utc <= format_utc(utc_now()) or not os.path.isfile(art.storage_path):
        raise ApiError(status_code=410, code="artifact.expired", message="Срок хранения документа истёк.")
    return _serialize_artifact(art)


@router.get("/builder/artifacts/{artifact_id}/content")
async def download_artifact_content(
    artifact_id: str,
    request: Request,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    art = (
        await db.execute(
            select(ArtifactModel).where(
                ArtifactModel.id == artifact_id,
                ArtifactModel.user_id == current_user.user_id,
            )
        )
    ).scalar_one_or_none()
    if art is None:
        raise ApiError(status_code=404, code="artifact.not-found", message="Артефакт не найден.")
    if art.expires_at_utc <= format_utc(utc_now()) or not os.path.isfile(art.storage_path):
        raise ApiError(status_code=410, code="artifact.expired", message="Срок хранения документа истёк.")

    data = Path(art.storage_path).read_bytes()
    total = len(data)
    encoded_name = quote(art.file_name)
    base_headers = {
        "Cache-Control": "no-store",
        "Accept-Ranges": "bytes",
        "Content-Disposition": f"attachment; filename*=UTF-8''{encoded_name}",
    }

    range_header = request.headers.get("Range") or request.headers.get("range")
    if range_header and range_header.startswith("bytes="):
        m = re.match(r"bytes=(\d+)-(\d*)", range_header)
        if m:
            start = int(m.group(1))
            end = int(m.group(2)) if m.group(2) else total - 1
            end = min(end, total - 1)
            if 0 <= start <= end < total:
                slice_bytes = data[start : end + 1]
                base_headers["Content-Range"] = f"bytes {start}-{end}/{total}"
                base_headers["Content-Length"] = str(len(slice_bytes))
                return Response(
                    content=slice_bytes,
                    status_code=206,
                    media_type=art.mime_type,
                    headers=base_headers,
                )

    base_headers["Content-Length"] = str(total)
    return Response(
        content=data,
        status_code=200,
        media_type=art.mime_type,
        headers=base_headers,
    )
