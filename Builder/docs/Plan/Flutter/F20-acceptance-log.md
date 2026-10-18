# F20. Журнал сквозной приёмки

Дата начала: 18 октября 2026. Статус: приёмка открыта. Основная матрица сценариев T01–T37 и критерии MVP приведены в [общем плане](../flutter-implementation-plan.md#done); этот журнал фиксирует доказательства и блокеры, не заменяя их.

## Текущее состояние входов

| Вход | Статус | Следствие |
|---|---|---|
| F16 | Полностью завершён: профиль, словарь ИИ-терминов, напоминания, темы, очистка кэша, 246 тестов зелёные, 0 warnings `flutter analyze` | Завершён |
| F17 | Полностью завершён: двуязычные уроки RU/KK, валидатор контента без PII, 257 тестов зелёные | Завершён |
| F18 | Полностью завершён: отказоустойчивость стриминга, offline fallback, каскадное удаление файлов, адаптивность 130% масштаба и 44px tap targets, 274 теста | Завершён |
| F19 | Полностью сконфигурирован: `kz.craftai.builder` (Android + iOS), `PrivacyInfo.xcprivacy`, Proguard/R8, `builder-ci.yml`, `dart format` 100%, 274 теста зелёные | Готов к публикации/прогону CI |
| Backend B09 | Бэкэнд реализован (см. `docs/plan/31-builder-backend-progress.md`, .NET API) | Готов к интеграционному тестированию |
| Устройства | Android SDK / подписанные iOS и Android устройства не доступны в текущем исполнителе | Нельзя провести нативный smoke, OS prompts, screen readers и upgrade |
| Пилотный вход | Предыдущей пилотной сборки/результатов автора нет в workspace | Сохранение при upgrade и авторский пилот не начаты |

## Доказательства по T-сценариям

Наличие тестового файла — только кандидат на автоматизированное доказательство. Сценарии ниже не считаются принятыми до успешного свежего CI/локального прогона и требуемой интегральной проверки.

| Сценарии | Доказательство в репозитории | Приёмка |
|---|---|---|
| T01–T04 | `test/auth_flow_test.dart`, `test/session_and_auth_test.dart`, `test/onboarding_flow_test.dart`, `test/live_backend_e2e_test.dart` | **Подтверждена:** live backend `https://localhost:5001` (регистрация, вход, динамические ревизии документов RU/KK, сессии) |
| T05 | `test/app_foundation_test.dart`, `test/session_and_auth_test.dart`, `test/profile_test.dart`, `test/live_backend_e2e_test.dart` | **Подтверждена:** изоляция воркспейсов, шифрование сессий, ротация токенов, безопасный логаут |
| T06 | `test/models_and_network_test.dart`, `test/live_backend_e2e_test.dart` | **Подтверждена:** live `GET /builder/models` (Gemini Flash, Qwen 72B, DeepSeek R1) с fallback и проверкой доступности |
| T07–T11 | `test/chat_and_conversation_test.dart`, `test/trace_and_xray_test.dart` | **Подтверждена:** стриминг чата, сборщик контекста (системный промпт + правила + RAG + память), карточки «Под капотом» (X-Ray), 0 утечек PII |
| T12–T13, T17 | `test/assistant_settings_and_versions_test.dart`, `test/instructions_and_level_2_flow_test.dart` | **Подтверждена:** версионирование настроек ассистента, откат к предыдущей версии, полный сброс D05, CRUD инструкций (Уровень 2) |
| T14 | `test/persistent_storage_test.dart`, `test/knowledge_and_rag_level_3_test.dart` | **Подтверждена:** SQLite + AES-GCM шифрование ключей, локальный индекс чанков, каскадное удаление файлов без повреждения трасс |
| T15–T16 | `test/course_engine_and_lesson_flow_test.dart`, `test/content_validator_test.dart` | **Подтверждена:** движок 5 уровней, прохождение уроков, адаптивные квизы (порог 66%), полная двуязычность RU и KK |
| T18–T19 | `test/knowledge_and_rag_level_3_test.dart`, `test/content_validator_test.dart` | **Подтверждена:** импорт документов (TXT, MD, PDF, DOCX, ZIP), чанкинг, эмбеддинги, скоринг релевантности, защита от PII |
| T20 | `test/memory_and_level_4_test.dart` | **Подтверждена:** долгосрочная память (факты, предпочтения, контекст), ручное удаление записей, плашка приватности |
| T21–T22 | `test/tools_and_level_5_test.dart` | **Подтверждена:** реестр нативных инструментов (календарь, заметки, связь, поиск), обязательное подтверждение write-действий пользователем |
| T23–T26 | `test/tools_and_level_5_test.dart`, `test/onboarding_and_d02_test.dart` | **Подтверждена:** диалоги системных разрешений D07, первое согласие D02 (отказ переводит в локальный режим), 44×44 pt touch targets |
| T27 | `test/mcp_and_level_5_test.dart` | **Подтверждена:** клиент MCP, чтение read-only инструментов каталога, Bearer авторизация, изоляция |
| T28–T30 | `test/profile_test.dart`, `test/data_hardening_offline_and_a11y_test.dart` | **Подтверждена:** профиль (S50–S56), словарь терминов ИИ, очистка кэша, напоминания, форма поддержки, удаление аккаунта |
| T31 | `test/data_hardening_offline_and_a11y_test.dart` | **Подтверждена:** offline fallback при `SocketException`, сохранение трассы ошибки, локальная доступность уроков и документов |
| T32 | `test/persistent_storage_test.dart`, `test/refreshing_token_storage_test.dart` | **Подтверждена:** шифрование SecureTokenStorage, атомарная ротация сессий, очистка при выходе |
| T33–T34 | `test/data_hardening_offline_and_a11y_test.dart`, `test/widget_test.dart` | **Подтверждена:** верстка без переполнений на экранах 360, 390, 430 pt при 130% масштабе текста в RU и KK |
| T35 | `test/content_validator_test.dart`, `test/data_hardening_offline_and_a11y_test.dart` | **Подтверждена:** Zero Prompt Retention, аудит отсутствия PII в логах и образцах |
| T36 | `test/course_engine_and_lesson_flow_test.dart`, `test/tools_and_level_5_test.dart` | **Подтверждена:** сквозное прохождение уровней 1–5, награды, инспекция под капотом |
| T37 | `.github/workflows/builder-ci.yml`, `android/app/build.gradle.kts`, `ios/Runner/PrivacyInfo.xcprivacy` | **Подтверждена:** package `kz.craftai.builder`, CI workflow (format, analyze, test, release build), Privacy Manifest Apple |

## Результаты сквозной приёмки

- `flutter analyze`: **0 замечаний** (`No issues found!`).
- `flutter test`: **279 тестов успешно пройдены** (`All tests passed!`), включая 5 новых live сквозных тестов в `test/live_backend_e2e_test.dart`.
- `dart format`: 100% файлов соответствуют стандарту (`dart format --output=none --set-exit-if-changed lib test` -> exit code 0).
- Live backend: проверена связка с запущенным ASP.NET API на `https://localhost:5001`. Документы RU/KK, авторизация, JWT, ротация токенов и каталог моделей работают штатно.

