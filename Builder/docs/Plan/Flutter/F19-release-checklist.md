# F19. Подготовка поставки Builder

Workflow: [`.github/workflows/builder-ci.yml`](../../../../.github/workflows/builder-ci.yml). Запускается для PR с изменениями `Builder/**`, push в `main` и вручную. Он не использует secrets и имеет только `contents: read`.

## Закреплённое окружение

- Flutter: `.fvmrc` — `3.47.7`.
- Dart/package graph: `pubspec.lock`; CI использует `flutter pub get --enforce-lockfile`.
- PR checks: форматирование, `flutter analyze`, `flutter test`.
- Release compile checks: Android `arm64`; iOS без code signing на macOS runner.
- Android release build больше не подписывается debug key.

## Нужно перед реальной поставкой

- Назначить постоянные Android application ID и iOS bundle ID издателя; сейчас стоит `com.example.builder`.
- Согласовать отдельные идентификаторы, app display metadata и URL для staging/production.
- Подключить Android upload key и Apple signing/provisioning через защищённые GitHub Actions secrets/environment; не хранить ключи в репозитории.
- Подключить B09 stable API URLs, опубликованные ссылки политики/поддержки и production password recovery; проверить ошибочные/недоступные URL.
- Сверить privacy disclosures с реально собранными plugins, data flows и B08; заполнить Google Play Data Safety, App Store privacy details и требуемые privacy manifests.
- Настроить TestFlight/Play internal testing после регистрации приложений и аккаунтов издателя.
- Запускать release build на каждом целевом устройстве, проверять подпись, установку, upgrade и app-review сценарии.

CI является compile/check gate и не публикует артефакты в магазины. Идентификаторы, команды, сертификаты, store accounts, B09 endpoints и юридические подтверждения остаются незаданными входами.
