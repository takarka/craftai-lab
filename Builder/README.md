# Builder

Самостоятельное Flutter-приложение. Исходники, зависимости и настройки находятся в этой папке; зависимостей от `../mobile` нет.

## Требования

Flutter 3.35.7 или новее (Dart 3.9+). Каркас платформ создан из официальных шаблонов Flutter 3.35.7. Для Android нужен Android SDK и JDK 17, для iOS — macOS и Xcode.

## Запуск

Из корня репозитория:

```sh
cd Builder
flutter pub get
flutter run
```

Запуск в браузере:

```sh
flutter run -d chrome
```

## Проверка

```sh
flutter analyze
flutter test
```

## Структура

- `lib/main.dart` — приложение Builder с пустым экраном.
- `pubspec.yaml` — собственный пакет `builder` и его зависимости.
- `android/`, `ios/`, `web/` — отдельные настройки платформ; идентификатор Android/iOS — `com.example.builder`.
- `test/widget_test.dart` — проверка стартового экрана.

Перед публикацией замените демонстрационный идентификатор `com.example.builder` своим и настройте подпись приложения.
