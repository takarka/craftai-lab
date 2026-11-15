import hashlib
import re
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from fastapi import Header, Request

from app.core.config import settings
from app.core.errors import ApiError

_ph = PasswordHasher()

_PASSWORD_POLICY = re.compile(r"^(?=.*[a-zA-Zа-яА-ЯёЁ])(?=.*\d).{8,128}$")


def utc_now() -> datetime:
    return datetime.now(UTC)


def format_utc(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    else:
        dt = dt.astimezone(UTC)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def validate_password_strength(password: str) -> None:
    if not _PASSWORD_POLICY.match(password):
        raise ApiError(
            status_code=400,
            code="AUTH_WEAK_PASSWORD",
            message="Пароль должен содержать не менее 8 символов, включая буквы и цифры.",
        )


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _ph.verify(password_hash, password)
    except (VerifyMismatchError, Exception):
        return False


def hash_token(raw_token: str) -> str:
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def generate_opaque_token() -> str:
    return secrets.token_urlsafe(32)


def create_access_token(
    *,
    user_id: str,
    email: str,
    name: str,
    role: str = "Teacher",
) -> tuple[str, datetime]:
    now = utc_now()
    expires_at = now + timedelta(minutes=settings.access_token_ttl_minutes)
    payload = {
        "sub": user_id,
        "name": name,
        "email": email,
        "role": role,
        "iss": settings.jwt_issuer,
        "iat": int(now.timestamp()),
        "exp": int(expires_at.timestamp()),
        "jti": str(uuid.uuid4()),
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm="HS256")
    return token, expires_at


class CurrentUser:
    def __init__(self, user_id: str, email: str, name: str, role: str) -> None:
        self.user_id = user_id
        self.email = email
        self.name = name
        self.role = role


async def get_current_user(
    request: Request,
    authorization: str | None = Header(default=None),
) -> CurrentUser:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise ApiError(
            status_code=401,
            code="auth.unauthorized",
            message="Требуется авторизация (Bearer token).",
        )
    raw_token = authorization[7:].strip()
    if not raw_token:
        raise ApiError(
            status_code=401,
            code="auth.unauthorized",
            message="Пустой токен авторизации.",
        )
    try:
        payload = jwt.decode(
            raw_token,
            settings.jwt_secret,
            algorithms=["HS256"],
            options={"require": ["sub", "exp"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise ApiError(
            status_code=401,
            code="auth.token-expired",
            message="Срок действия сессии истёк.",
        ) from exc
    except jwt.PyJWTError as exc:
        raise ApiError(
            status_code=401,
            code="auth.invalid-token",
            message="Недействительный токен авторизации.",
        ) from exc

    user_id = str(payload.get("sub", ""))
    if not user_id:
        raise ApiError(
            status_code=401,
            code="auth.invalid-token",
            message="Отсутствует идентификатор пользователя.",
        )

    return CurrentUser(
        user_id=user_id,
        email=str(payload.get("email", "")),
        name=str(payload.get("name", "")),
        role=str(payload.get("role", "Teacher")),
    )
