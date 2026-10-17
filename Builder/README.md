# Craft Builder

Самостоятельное Flutter-приложение экосистемы CraftAI. Учитель проходит курс и собирает ИИ-ассистента. Начата реализация приложения: bootstrap, конфигурация, защищённые маршруты и RU/KK. Пока настоящий вход CraftAI не подключён, приложение показывает сообщение о его недоступности. UI Kit доступен отдельным DEV-входом. Зависимостей от `mobile` нет.

## Запуск

Проверено на Flutter 3.47.7 / Dart 3.13.5. Минимум текущих зависимостей: Flutter 3.44 / Dart 3.12; native minimum OS ещё уточняется в F01.

```sh
cd Builder
flutter pub get
flutter run -d chrome --dart-define=APP_ENV=dev
```

Также сохранены отдельные проекты Android и iOS с идентификатором `com.example.builder`. Для сборки Android нужны Android SDK и JDK 17; для iOS — macOS и Xcode. Перед публикацией замените пример идентификатора и настройте подпись.

Публичная конфигурация: `APP_ENV=dev|staging|prod` (по умолчанию `prod`), `CRAFTAI_API_BASE_URL=https://…` — только base URL CraftAI, без ключей/query/fragment. До подключения API URL можно не задавать: приложение не подставляет вымышленный сервер и не отправляет запросы. HTTP допускается только для loopback в dev. Даже при заданном URL реальная авторизация ещё не реализована.

```sh
flutter run --dart-define=APP_ENV=staging --dart-define=CRAFTAI_API_BASE_URL=https://your-craftai-host/api
```

На Linux с установленным Chromium можно задать `CHROME_EXECUTABLE=/usr/bin/chromium` перед `flutter run -d chrome`. Android требует Android SDK, iOS — macOS/Xcode; успешный web preview не заменяет их проверки.

## UI Kit

Каталог запускается отдельно; `main.dart` его не импортирует. В release DEV-вход отклоняется.

```sh
flutter run -t lib/main_gallery.dart -d chrome
```

Четыре раздела: основы, контролы, композиции и персонаж. Переключатели, поля, чипы, состояния сообщений, подтверждения и выбор модулей можно проверить прямо в каталоге. Каталог не отправляет запросы к модели и не создаёт события в календаре.

- `lib/app/` — bootstrap, окружения, router, ARB/RU/KK и временные страницы каркаса.
- `lib/features/session/` — интерфейс сессии без имитации рабочего входа.
- `lib/core/platform/` — платформенные возможности, отдельно от OS permissions.
- `lib/ui_kit/` — переиспользуемые токены, тема, иконки, компоненты.
- `lib/gallery/` — примеры использования компонентов.
- `assets/` — локальные шрифты с лицензиями, оригинальные SVG-иконки и персонаж.
- `docs/ui-kit.md` — API, соответствие макетам, состояния, решения по доступности.
- `test/` — адаптивность и поведение интерактивных компонентов.

```sh
flutter analyze
flutter test
flutter build web --release
```

## Источники

`docs/` содержит концепцию, ТЗ, функциональные требования, методичку курса и аудит пользовательских сценариев. `design/` содержит оригинальные экспорты макетов `UK1–UK4`, `Char` и экранов приложения. Экспорты `.dc.html` используют рантайм Design-артефакта; отдельный статический просмотрщик — `design/web/`. Рабочая реализация UI Kit написана на Flutter.

[План Flutter](docs/Plan/Flutter/README.md) · [Статус F00/F01/F02](docs/Plan/Flutter/implementation-status.md).
