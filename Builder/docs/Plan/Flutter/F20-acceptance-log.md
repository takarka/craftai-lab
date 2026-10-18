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

| Сценарии | Кандидат в репозитории | Приёмка |
|---|---|---|
| T01–T04 | `test/auth_flow_test.dart`, `test/session_and_auth_test.dart`, `test/onboarding_flow_test.dart` | Открыта; live CraftAI и свежий зелёный CI не подтверждены |
| T05 | `test/app_foundation_test.dart`, `test/session_and_auth_test.dart`, `test/profile_test.dart` | Открыта; owner isolation + late async на реальных lifecycle не пройдены |
| T06 | `test/models_and_network_test.dart` | Открыта; реальный изменившийся B02 catalog отсутствует |
| T07–T11 | `test/chat_and_conversation_test.dart`, `test/trace_and_xray_test.dart` | Открыта; запуск suite остановлен Flutter до старта тестов из-за занятого `Builder/build/native_assets/windows/sqlite3.dll`; реальный payload/B09 не сверен |
| T12–T13, T17 | `test/assistant_settings_and_versions_test.dart`, `test/instructions_and_level_2_flow_test.dart` | Открыта; реальные restore/delete semantics не подтверждены на устройстве |
| T14 | `test/persistent_storage_test.dart`, `test/knowledge_and_rag_level_3_test.dart` | Открыта; crash/indexing/reset и последующая native проверка не пройдены |
| T15–T16 | `test/course_engine_and_lesson_flow_test.dart` | Открыта; пять уроков целиком не локализованы/не пройдены вручную на RU и KK |
| T18–T19 | `test/knowledge_and_rag_level_3_test.dart` | Открыта; повреждённые/пограничные реальные файлы и full RAG matrix не приняты |
| T20 | `test/memory_and_level_4_test.dart` | Открыта; end-to-end trace и межсессионная native проверка не пройдены |
| T21–T22 | `test/tools_and_level_5_test.dart` | Открыта; реальные write-action и replay проверки не пройдены на устройствах |
| T23–T26 | `test/tools_and_level_5_test.dart`, `test/onboarding_and_d02_test.dart` | Открыта; OS calendar/permission/dialer/compose/search проверить можно только на согласованных устройствах |
| T27 | `test/mcp_and_level_5_test.dart` | Открыта; реальный connector и revoke-in-flight не подтверждены |
| T28–T30 | `test/profile_test.dart`, `test/profile_and_f16_test.dart` | Открыта; B06/B07 delete/usage/support API отсутствуют; два widget-теста в F16 падают по timeout |
| T31 | Unit/widget покрытие распределено между course/profile/chat тестами | Открыта; полная offline/content update матрица не пройдена |
| T32 | `test/persistent_storage_test.dart`, `test/refreshing_token_storage_test.dart` | Открыта; native encryption, backup/restore, reinstall и full disk не пройдены |
| T33–T34 | Локализационные/widget тесты в нескольких test-файлах | Открыта; все экраны, 3 ширины, 130%, TalkBack и VoiceOver не проверены |
| T35 | Статические замечания F18 в `F18-audit.md` | Открыта; app binary, backend/APM и реальные network traces не проверены |
| T36 | Полная вертикаль частично покрыта course/tool тестами | Открыта; требует live B09, пяти evidence-based уроков и реального revoke MCP |
| T37 | CI-компиляционные jobs описаны в `.github/workflows/builder-ci.yml` | Открыта; workflow не запускался, signing, store metadata и установка на устройства не выполнены |

## Следующий безопасный прогон

1. Повторить автоматические проверки Flutter после завершения активного `flutter_tester`; текущий запуск test suite не дошёл до выполнения тестов из-за locked native artifact.
2. После зелёного baseline запустить GitHub Actions и сохранить ссылку на CI run.
3. Получить B08/B09 и продуктовые IDs/аккаунты, не помещая credentials в репозиторий.
4. Повторить приёмку на авторских Android/iOS устройствах; до этого не назначать пилот и не заявлять готовность MVP.

## Локальные попытки в этой приёмке

- `flutter analyze`: свежий прогон завершился `No issues found`.
- `flutter test --reporter expanded`: тесты начали выполняться, достигли 240+ успешных кейсов, но F16 profile и assistant-language widget tests завершились `pumpAndSettle timed out`; запуск оставил работающий `flutter_tester` (PID 27448) и заблокированный SQLite native artifact. Не завершал процесс, чтобы не прерывать его работу. Повторный точечный запуск не стартовал из-за блокировки того же файла.
- Android/iOS build, workflow dispatch и device checks не запускались.
