import os
import shutil
import uuid
from datetime import timedelta

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import (
    AttachmentModel,
    ContentReportModel,
    PasswordResetTokenModel,
    RefreshSessionModel,
    TokenUsageLedgerModel,
    UserModel,
    get_db,
)
from app.core.errors import ApiError
from app.core.security import (
    CurrentUser,
    create_access_token,
    format_utc,
    generate_opaque_token,
    get_current_user,
    hash_password,
    hash_token,
    utc_now,
    validate_password_strength,
    verify_password,
)

router = APIRouter()

LEGAL_DOCS = {
    "ru": {
        "language": "ru",
        "termsRevision": "2026.1-ru",
        "privacyRevision": "2026.1-ru",
        "termsText": (
            "Пользовательское соглашение CraftAI Lab.\n\n"
            "Настоящее соглашение регулирует использование образовательного ИИ-ассистента "
            "Craftai Lab учителями и специалистами образования."
        ),
        "privacyText": (
            "Политика конфиденциальности персональных данных CraftAI Lab.\n\n"
            "Мы обеспечиваем защиту данных аккаунта, событий календаря и временно обрабатываемых "
            "учебных материалов. Не загружайте персональные данные учащихся."
        ),
    },
    "kk": {
        "language": "kk",
        "termsRevision": "2026.1-kk",
        "privacyRevision": "2026.1-kk",
        "termsText": (
            "CraftAI Lab пайдаланушы келісімі.\n\n"
            "Бұл келісім мұғалімдер мен білім беру мамандарының Craftai Lab "
            "білім беру ЖИ-көмекшісін пайдалану тәртібін реттейді."
        ),
        "privacyText": (
            "CraftAI Lab дербес деректерді қорғау саясаты.\n\n"
            "Біз аккаунт деректерін, күнтізбе оқиғаларын және уақытша өңделетін "
            "оқу материалдарын қорғауды қамтамасыз етеміз. Оқушылардың дербес деректерін жүктемеңіз."
        ),
    },
}


class LoginRequest(BaseModel):
    email: str
    password: str


class RegisterRequest(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    email: str = Field(min_length=3, max_length=255)
    password: str
    termsRevision: str
    privacyRevision: str
    language: str = "ru"


class RefreshRequest(BaseModel):
    refreshToken: str


class ForgotPasswordRequest(BaseModel):
    email: str
    language: str = "ru"


class ResetPasswordRequest(BaseModel):
    token: str
    newPassword: str


class ChangePasswordRequest(BaseModel):
    newPassword: str


class LogoutRequest(BaseModel):
    refreshToken: str | None = None


class ReportRequest(BaseModel):
    requestId: str = Field(min_length=1, max_length=64)
    reason: str = Field(min_length=1, max_length=64)
    comment: str | None = Field(default=None, max_length=1000)


async def _issue_session_tokens(db: AsyncSession, user: UserModel) -> dict:
    access_token, access_exp = create_access_token(
        user_id=user.id,
        email=user.email,
        name=user.name,
        role=user.role,
    )
    raw_refresh = generate_opaque_token()
    now = utc_now()
    refresh_exp = now + timedelta(days=settings.refresh_token_ttl_days)

    session_row = RefreshSessionModel(
        id=str(uuid.uuid4()),
        user_id=user.id,
        token_hash=hash_token(raw_refresh),
        expires_at_utc=format_utc(refresh_exp),
        created_at_utc=format_utc(now),
    )
    db.add(session_row)
    await db.commit()

    return {
        "userId": user.id,
        "email": user.email,
        "fullName": user.name,
        "accessToken": access_token,
        "refreshToken": raw_refresh,
        "accessTokenExpiresAtUtc": format_utc(access_exp),
        "refreshExpiresAtUtc": format_utc(refresh_exp),
        "mustChangePassword": user.must_change_password,
    }


@router.get("/mobile/auth/documents")
async def get_legal_documents(lang: str = Query(default="ru")) -> dict:
    code = "kk" if lang.lower().startswith("kk") else "ru"
    return LEGAL_DOCS[code]


@router.post("/mobile/auth/login")
async def login(body: LoginRequest, db: AsyncSession = Depends(get_db)) -> dict:
    email = body.email.strip().lower()
    stmt = select(UserModel).where(UserModel.email == email, UserModel.deleted_at_utc.is_(None))
    user = (await db.execute(stmt)).scalar_one_or_none()
    if user is None or not verify_password(body.password, user.password_hash):
        raise ApiError(
            status_code=401,
            code="login.invalid-credentials",
            message="Неверный e-mail или пароль.",
        )
    return await _issue_session_tokens(db, user)


@router.post("/mobile/auth/register")
async def register(body: RegisterRequest, db: AsyncSession = Depends(get_db)) -> dict:
    validate_password_strength(body.password)
    email = body.email.strip().lower()
    if "@" not in email or "." not in email.split("@")[-1]:
        raise ApiError(
            status_code=400,
            code="auth.invalid-email",
            message="Некорректный формат e-mail.",
        )

    existing = (await db.execute(select(UserModel).where(UserModel.email == email))).scalar_one_or_none()
    if existing is not None:
        raise ApiError(
            status_code=409,
            code="auth.account-exists",
            message="Аккаунт с таким e-mail уже существует.",
        )

    user = UserModel(
        id=str(uuid.uuid4()),
        email=email,
        name=body.name.strip(),
        password_hash=hash_password(body.password),
        role="Teacher",
        must_change_password=False,
        terms_revision=body.termsRevision.strip() or "2026.1-ru",
        privacy_revision=body.privacyRevision.strip() or "2026.1-ru",
        language="kk" if body.language.lower().startswith("kk") else "ru",
        created_at_utc=format_utc(utc_now()),
    )
    db.add(user)
    await db.commit()
    return await _issue_session_tokens(db, user)


@router.post("/mobile/auth/refresh")
async def refresh_tokens(body: RefreshRequest, db: AsyncSession = Depends(get_db)) -> dict:
    raw = body.refreshToken.strip()
    if not raw:
        raise ApiError(status_code=401, code="auth.invalid-refresh", message="Токен обновления отсутствует.")

    thash = hash_token(raw)
    stmt = select(RefreshSessionModel).where(RefreshSessionModel.token_hash == thash)
    session_row = (await db.execute(stmt)).scalar_one_or_none()
    now_str = format_utc(utc_now())

    if session_row is None or session_row.revoked_at_utc is not None or session_row.expires_at_utc <= now_str:
        raise ApiError(status_code=401, code="auth.refresh-expired", message="Сессия истекла или отозвана.")

    user = (
        await db.execute(
            select(UserModel).where(UserModel.id == session_row.user_id, UserModel.deleted_at_utc.is_(None))
        )
    ).scalar_one_or_none()
    if user is None:
        raise ApiError(status_code=401, code="auth.user-not-found", message="Аккаунт недоступен.")

    # Rotate refresh token atomically
    session_row.revoked_at_utc = now_str
    await db.commit()

    return await _issue_session_tokens(db, user)


@router.post("/mobile/auth/forgot-password")
async def forgot_password(body: ForgotPasswordRequest, db: AsyncSession = Depends(get_db)) -> dict:
    email = body.email.strip().lower()
    user = (
        await db.execute(select(UserModel).where(UserModel.email == email, UserModel.deleted_at_utc.is_(None)))
    ).scalar_one_or_none()
    if user is not None:
        raw_reset = generate_opaque_token()
        now = utc_now()
        reset_row = PasswordResetTokenModel(
            id=str(uuid.uuid4()),
            user_id=user.id,
            token_hash=hash_token(raw_reset),
            expires_at_utc=format_utc(now + timedelta(minutes=30)),
        )
        db.add(reset_row)
        await db.commit()
    # Always return 200 without revealing if the email exists (B01-04)
    return {"status": "accepted"}


@router.post("/mobile/auth/reset-password")
async def reset_password(body: ResetPasswordRequest, db: AsyncSession = Depends(get_db)) -> dict:
    validate_password_strength(body.newPassword)
    thash = hash_token(body.token.strip())
    now_str = format_utc(utc_now())
    stmt = select(PasswordResetTokenModel).where(PasswordResetTokenModel.token_hash == thash)
    token_row = (await db.execute(stmt)).scalar_one_or_none()

    if token_row is None or token_row.consumed_at_utc is not None or token_row.expires_at_utc <= now_str:
        raise ApiError(
            status_code=400,
            code="auth.invalid-reset-token",
            message="Ссылка для сброса пароля недействительна или устарела.",
        )

    user = (
        await db.execute(select(UserModel).where(UserModel.id == token_row.user_id, UserModel.deleted_at_utc.is_(None)))
    ).scalar_one_or_none()
    if user is None:
        raise ApiError(status_code=400, code="auth.invalid-reset-token", message="Аккаунт не найден.")

    token_row.consumed_at_utc = now_str
    user.password_hash = hash_password(body.newPassword)
    user.must_change_password = False

    # Revoke all existing refresh sessions on password reset
    sessions = (
        await db.execute(
            select(RefreshSessionModel).where(
                RefreshSessionModel.user_id == user.id,
                RefreshSessionModel.revoked_at_utc.is_(None),
            )
        )
    ).scalars().all()
    for s in sessions:
        s.revoked_at_utc = now_str

    await db.commit()
    return {"status": "ok"}


@router.post("/mobile/auth/change-password")
async def change_password(
    body: ChangePasswordRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    validate_password_strength(body.newPassword)
    user = (await db.execute(select(UserModel).where(UserModel.id == current_user.user_id))).scalar_one_or_none()
    if user is None:
        raise ApiError(status_code=401, code="auth.user-not-found", message="Пользователь не найден.")
    user.password_hash = hash_password(body.newPassword)
    user.must_change_password = False
    await db.commit()
    return {"status": "ok"}


@router.post("/mobile/auth/logout")
async def logout(
    body: LogoutRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    now_str = format_utc(utc_now())
    if body.refreshToken:
        thash = hash_token(body.refreshToken.strip())
        stmt = select(RefreshSessionModel).where(
            RefreshSessionModel.user_id == current_user.user_id,
            RefreshSessionModel.token_hash == thash,
        )
        row = (await db.execute(stmt)).scalar_one_or_none()
        if row is not None:
            row.revoked_at_utc = now_str
    else:
        stmt = select(RefreshSessionModel).where(
            RefreshSessionModel.user_id == current_user.user_id,
            RefreshSessionModel.revoked_at_utc.is_(None),
        )
        for row in (await db.execute(stmt)).scalars().all():
            row.revoked_at_utc = now_str

    await db.commit()
    return {"status": "ok"}


@router.get("/me/usage")
async def get_account_usage(
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    now = utc_now()
    period_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    if period_start.month == 12:
        period_end = period_start.replace(year=period_start.year + 1, month=1)
    else:
        period_end = period_start.replace(month=period_start.month + 1)

    stmt = select(
        func.coalesce(func.sum(TokenUsageLedgerModel.input_tokens), 0),
        func.coalesce(func.sum(TokenUsageLedgerModel.output_tokens), 0),
        func.coalesce(func.sum(TokenUsageLedgerModel.total_tokens), 0),
    ).where(
        TokenUsageLedgerModel.user_id == current_user.user_id,
        TokenUsageLedgerModel.created_at_utc >= format_utc(period_start),
    )
    row = (await db.execute(stmt)).one()
    return {
        "status": "available",
        "tokens": {
            "inputTokens": int(row[0]),
            "outputTokens": int(row[1]),
            "totalTokens": int(row[2]),
        },
        "periodStartUtc": format_utc(period_start),
        "periodEndUtc": format_utc(period_end),
        "updatedAtUtc": format_utc(now),
    }


@router.post("/builder/reports", status_code=201)
async def create_report(
    body: ReportRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    report_id = str(uuid.uuid4())
    report = ContentReportModel(
        id=report_id,
        user_id=current_user.user_id,
        request_id=body.requestId,
        reason=body.reason,
        comment=body.comment,
        created_at_utc=format_utc(utc_now()),
    )
    db.add(report)
    await db.commit()
    return {"id": report_id, "status": "received"}


@router.delete("/me/account", status_code=204)
async def delete_account(
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    uid = current_user.user_id
    # Delete physical files for user
    user_storage_dir = os.path.join(settings.storage_dir, uid)
    if os.path.isdir(user_storage_dir):
        shutil.rmtree(user_storage_dir, ignore_errors=True)

    # Erase all user-owned entities across all tables (B07-02, EB-02, EB-06)
    await db.execute(delete(AttachmentModel).where(AttachmentModel.user_id == uid))
    await db.execute(delete(TokenUsageLedgerModel).where(TokenUsageLedgerModel.user_id == uid))
    await db.execute(delete(RefreshSessionModel).where(RefreshSessionModel.user_id == uid))
    await db.execute(delete(PasswordResetTokenModel).where(PasswordResetTokenModel.user_id == uid))
    await db.execute(delete(ContentReportModel).where(ContentReportModel.user_id == uid))
    await db.execute(delete(UserModel).where(UserModel.id == uid))
    await db.commit()
