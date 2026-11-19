# Craftai Lab — Standalone Backend

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

Постоянное хранение, миграции, перенос существующей SQLite и проверка
восстановления описаны в [PERSISTENCE.md](PERSISTENCE.md). Вне `dev`/`test`
обязателен `CRAFTAI_DATABASE_URL` PostgreSQL. При наличии старой БД без версии
сначала сделайте копию и выполните проверенное принятие legacy-схемы.

```bash
cd backend
uv run pytest -v
```

## Lab API — фаза LM01

Маршруты `/lab/v1` используют ту же Bearer-авторизацию, что мобильный API.
Схема новых таблиц `lab_*` создаётся при старте, каталог двух скиллов заполняется
идемпотентно. SQLite и PostgreSQL используют существующее подключение приложения.

- `GET/POST /agents`, `GET/PATCH/DELETE /agents/{id}` — до пяти активных агентов;
  изменение настроек создаёт неизменяемую версию. Чужие объекты возвращают 404.
- `POST /agents/{id}/copy` — только конфигурация; можно передать `{"name": "Копия"}`.
- `POST /agents/{id}/reset` — очистка памяти, материалов, диалогов, новый epoch и
  отмена активных запусков/подтверждений. Прогресс курса сохраняется.
- `GET /models`, `GET /skills` — каталоги с флагами совместимости и версиями.
- `GET/PUT /course/progress` — `course_version`, `current_lesson` (1–7),
  `completed_lessons`. Достигнутые уроки объединяются и сохраняются при обновлении курса.

Пример тела создания агента:

```json
{
  "name": "Задания по математике",
  "subject": "Математика",
  "grade": "5",
  "instruction": "Подготовь задания от простого к сложному.",
  "skills": [{"skill_id": "prepare_tasks", "version": 1}],
  "permissions": {"save_material": false, "search_materials": false}
}
```

Имена полей — snake_case. Инструкция и редактируемая часть скилла ограничены
5000 символами, материал — 10000. Невалидные запросы Lab возвращают 422,
превышение лимита агентов — `409 agents.limit-reached`.
Два слота моделей задаются `CRAFTAI_LAB_MODEL_1_ID` / `CRAFTAI_LAB_MODEL_2_ID`
и соответствующими `SUPPORTS_TOOLS` / `SUPPORTS_VISION` из `.env.example`.
Пока Q-2 не решён, пустые слоты помечены недоступными, `model_id` агента может
быть null; скрытой подстановки модели нет. Скиллы: `prepare_tasks`, `check_answer`.

Проверка LM01: `uv run pytest tests/test_lab_agents.py tests/test_api_contracts.py -q`.
