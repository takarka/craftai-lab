# F19. Подготовка поставки Builder

Workflow: [`.github/workflows/builder-ci.yml`](../../../../.github/workflows/builder-ci.yml). Запускается для PR с изменениями `Builder/**`, push в `main` и вручную. Он не использует secrets и имеет только `contents: read`.

## Закреплённое окружение

- Flutter: `.fvmrc` — `3.47.7`.
- Dart/package graph: `pubspec.lock`; CI использует `flutter pub get --enforce-lockfile`.
- PR checks: форматирование `dart format`, `flutter analyze` (0 warnings), `flutter test` (274 tests).
- Release compile checks: Android `arm64`; iOS без code signing на macOS runner (`actions/checkout@v4`, `actions/setup-java@v4`).
- Android release build больше не подписывается debug key; поддерживает injection подписи через CI-переменные окружения без сохранения секретов в git.
- Proguard / R8 правила: `proguard-rules.pro` для сохранения интерфейсов Flutter, sqflite, flutter_secure_storage.
- Идентификаторы: `kz.craftai.builder` (Android `namespace` и `applicationId`, iOS `PRODUCT_BUNDLE_IDENTIFIER`). Название: `Craft Builder`.
- Apple Privacy Manifest: `ios/Runner/PrivacyInfo.xcprivacy` зарегистрирован в проекте с типами `NSPrivacyAccessedAPITypeUserDefaults` (`CA92.1`) и `NSPrivacyAccessedAPITypeFileTimestamp` (`C617.1`).
- Права доступа Android: добавлены `INTERNET` и `ACCESS_NETWORK_STATE` в основной `AndroidManifest.xml`.

## Шаги для публикации в магазины (Release Ops)

- Добавить production/staging credentials в GitHub Actions Secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` для Android; `APP_STORE_CONNECT_API_KEY` и provisioning profiles для iOS.
- Для staging сборки указывать: `--dart-define=APP_ENV=staging --dart-define=CRAFTAI_API_BASE_URL=https://staging-api.craftai.kz`.
- Для production сборки указывать: `--dart-define=APP_ENV=prod --dart-define=CRAFTAI_API_BASE_URL=https://api.craftai.kz`.
- При выгрузке в App Store Connect и Google Play Console:
  - Использовать подготовленный Privacy Manifest и декларации (нет межсайтового трекинга, данные хранятся локально, связь с облаком — только при авторизации/сессиях).
  - Настроить дорожки внутреннего тестирования (TestFlight Internal Group / Google Play Internal App Sharing).
