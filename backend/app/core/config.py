from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="CRAFTAI_",
        extra="ignore",
    )

    app_env: str = "dev"
    host: str = "0.0.0.0"
    port: int = 5001

    # Database: defaults to local async SQLite for instant zero-config startup,
    # or PostgreSQL (postgresql+asyncpg://...) in Docker/production.
    database_url: str = "sqlite+aiosqlite:///./data/builder.db"

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
