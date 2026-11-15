# Craft AI Builder — Standalone Backend

Автономный модульный монолит на **Python 3.12+ / FastAPI / SQLAlchemy 2.0 (Async)**, полностью реализующий все 32 HTTP/SSE/JSON-RPC эндпоинта мобильного приложения `Builder` (Craft AI).

## Архитектурные модули

- **`app/modules/auth.py`** — Аутентификация (`/mobile/auth/*`), ротация refresh-токенов, сброс/смена пароля, квоты токенов (`GET /me/usage`), жалобы на ИИ-контент (`POST /builder/reports`) и каскадное удаление аккаунта (`DELETE /me/account`).
- **`app/modules/models_and_chat.py`** — Каталог моделей (`GET /builder/models`), потоковый SSE-чат (`POST /builder/chat/completions` со событиями `start`, `text_delta`, `usage`, `terminal`) с поддержкой OpenRouter и локального фолбэка, а также веб-поиск (`POST /builder/search`) через Brave Search API с очисткой bidi-символов и защитой от SSRF.
- **`app/modules/calendar.py`** — Календарь (`/builder/calendar/*`), разворот повторяющихся событий (`DAILY`, `WEEKLY`, `MONTHLY`) с учётом IANA `ZoneInfo`, оптимистичная блокировка `ETag` / `If-Match` (`412 calendar.version-conflict`), редактирование отдельных вхождений (`occurrences/{date}`) и дельта-синхронизация (`GET /builder/calendar/changes?cursor=`).
- **`app/modules/documents.py`** — Файловый конвейер (`/builder/attachments`, `/builder/document-jobs`, `/builder/artifacts`), проверка magic bytes (`TXT`, `DOCX`, `PDF`), отклонение зашифрованных и сканированных PDF без текстового слоя (`file.encrypted`, `file.no-text-layer`), генерация реальных `.docx` и `.pdf` с кириллическим/казахским шрифтом (`Onest`) и докачка артефактов через `Range: bytes=N-` (`206 Partial Content`).
- **`app/modules/schedules.py`** — ИИ-расписания (`/builder/schedules/*`, `/builder/runs/*`, `/builder/devices/*`), шаблоны `daily-brief` и `idea-generator`, ручной запуск (`run-now`) и фоновый планировщик.
- **`app/modules/mcp.py`** — Встроенный JSON-RPC 2.0 сервер (`POST /mcp/v1`) для образовательных инструментов (`tools/list`, `tools/call`: `search_lessons`, `get_lesson`).

## Быстрый старт (локально через `uv`)

```bash
cd backend
uv venv
uv pip install -e ".[dev]"
uv run uvicorn app.main:app --host 0.0.0.0 --port 5001 --reload
```

По умолчанию создаётся локальная база SQLite (`craftai_dev.db`), директория `./storage` и тестовый аккаунт для E2E-тестов Flutter:
- **Email:** `local-dev@craft-ai.local`
- **Password:** `LocalDevPass123!`

## Запуск в Docker (PostgreSQL 16 + API)

```bash
cd backend
docker compose up --build -d
```

## Запуск тестов

```bash
cd backend
uv run pytest -v
```
