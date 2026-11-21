from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url


def normalize_database_url(value: str) -> str:
    """Accept provider URLs while always selecting an asynchronous driver."""
    try:
        url = make_url(value)
    except Exception:
        raise ValueError("Invalid database URL.") from None
    if url.drivername in {"postgres", "postgresql"}:
        url = url.set(drivername="postgresql+asyncpg")
    elif url.drivername == "sqlite":
        url = url.set(drivername="sqlite+aiosqlite")
    if url.drivername not in {"postgresql+asyncpg", "sqlite+aiosqlite"}:
        raise ValueError("Use PostgreSQL/asyncpg or SQLite/aiosqlite.")
    if url.drivername == "postgresql+asyncpg" and "sslmode" in url.query:
        if "ssl" in url.query:
            raise ValueError("Specify only one of ssl or sslmode.")
        ssl = url.query["sslmode"]
        url = url.difference_update_query(["sslmode"]).update_query_dict({"ssl": ssl})
    return url.render_as_string(hide_password=False)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="CRAFTAI_",
        extra="ignore",
        hide_input_in_errors=True,
    )

    app_env: str = "dev"
    host: str = "0.0.0.0"
    port: int = 5001
    # JSON array of browser origins; paths such as /craftai-lab/ are not origins.
    cors_origins: list[str] = [
        "http://localhost:3000",
        "http://localhost:8080",
        "https://takarka.github.io",
    ]

    @field_validator("cors_origins")
    @classmethod
    def explicit_browser_origins(cls, value: list[str]) -> list[str]:
        from urllib.parse import urlsplit

        for origin in value:
            parsed = urlsplit(origin)
            if (
                parsed.scheme not in {"http", "https"}
                or not parsed.netloc
                or parsed.hostname is None
                or "*" in origin
                or parsed.username is not None
                or parsed.password is not None
                or parsed.path
                or parsed.query
                or parsed.fragment
            ):
                raise ValueError("CORS origins must be explicit HTTP(S) origins without a path or credentials.")
        return value

    # Database: defaults to local async SQLite for instant zero-config startup,
    # or PostgreSQL (postgresql+asyncpg://...) in Docker/production.
    database_url: str = "sqlite+aiosqlite:///./data/builder.db"

    @field_validator("database_url", mode="before")
    @classmethod
    def async_database_driver(cls, value: str) -> str:
        return normalize_database_url(value)

    @model_validator(mode="after")
    def persistent_production_database(self):
        if self.app_env not in {"dev", "test"} and not self.database_url.startswith("postgresql+asyncpg://"):
            raise ValueError("Set CRAFTAI_DATABASE_URL to PostgreSQL outside dev/test; ephemeral SQLite is disabled.")
        return self

    # File storage directory (or S3/MinIO bucket path)
    storage_dir: str = "./data/storage"

    # Security
    jwt_secret: str = "dev-secret-change-in-production-craftai-builder-2026-key-32b"
    jwt_issuer: str = "craftai-builder"
    access_token_ttl_minutes: int = 15
    refresh_token_ttl_days: int = 30

    # External Providers (optional in dev; falls back to deterministic local execution if empty)
    openrouter_api_key: str = ""
    openrouter_base_url: str = "https://openrouter.ai/api/v1"
    # LM01: explicit catalog slots; provider IDs/capabilities await decision Q-2.
    lab_model_1_id: str = ""
    lab_model_1_supports_tools: bool = False
    lab_model_1_supports_vision: bool = False
    lab_model_2_id: str = ""
    lab_model_2_supports_tools: bool = False
    lab_model_2_supports_vision: bool = False
    search_provider: str = "brave"  # brave | tavily | serper | local
    search_api_key: str = ""

    # Firebase Cloud Messaging (FCM HTTP v1)
    fcm_project_id: str = ""
    fcm_service_account_json: str = ""

    # Background scheduler & worker
    enable_embedded_worker: bool = True
    scheduler_tick_seconds: int = 15


settings = Settings()
