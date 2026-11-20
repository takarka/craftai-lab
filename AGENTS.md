# Repository Guidelines

## Project Structure & Module Organization

This repository contains two independent Flutter applications: `Builder/` (Craftai Lab, the main application) and `mobile/` (a minimal Flutter scaffold). Run Flutter commands from the relevant application directory; keep their dependencies separate.

In `Builder/lib/`, use `app/` for bootstrap, routing, and localization; `core/` for shared infrastructure; `features/` for domain features; and `ui_kit/` for reusable components. Features organize code into `domain/`, `infrastructure/`, and `presentation/` layers where applicable. Component examples live in `gallery/`. Assets belong in `Builder/assets/`, tests in `Builder/test/` and `Builder/integration_test/`, and specifications, plans, and design references in `Builder/docs/` and `Builder/design/`.

## Build, Test, and Development Commands

Use the Flutter version pinned in `Builder/.fvmrc`. From `Builder/`:

- `flutter pub get --enforce-lockfile` — install locked dependencies, matching CI.
- `flutter run -d chrome --dart-define=APP_ENV=dev` — run the development web app.
- `flutter run -t lib/main_gallery.dart -d chrome` — open the UI component gallery.
- `dart format lib test test_live` — format application and test code.
- `flutter analyze` — run static analysis and Flutter lint rules.
- `flutter test --reporter expanded` — run the test suite.
- `flutter build apk --release --target-platform android-arm64 --dart-define=APP_ENV=staging` — compile the Android release used by CI; requires Android SDK and JDK 17.

## Coding Style & Naming Conventions

Use Dart's formatter, two-space indentation, and each app's `analysis_options.yaml` (`flutter_lints`). Name files `snake_case.dart`, types `UpperCamelCase`, and members `lowerCamelCase`. Reuse UI kit tokens and components. Maintain Russian and Kazakh strings in `lib/app/localization/app_ru.arb` and `app_kk.arb`; regenerate localization with `flutter gen-l10n`.

## Testing Guidelines

Do not run the full test suite after every task or edit. Run focused checks for affected behavior; use the full suite when changes have broad impact, CI requires it, or the user requests it. Skip tests for documentation-only changes. Repeat passing checks only when further changes or new evidence justify it.

Use `flutter_test` for unit and widget tests, named `*_test.dart`. Run focused checks with `flutter test test/auth_flow_test.dart`. Native integration tests use `integration_test`: run `flutter test integration_test/ef00_upgrade_test.dart -d <device-id>`. Live backend tests live separately in `Builder/test_live/` and are excluded from the default `flutter test` discovery. With a local dev API running, execute `flutter test test_live/live_backend_e2e_test.dart`; the default URL is `http://127.0.0.1:5001`. Override it with `--dart-define=LIVE_BACKEND_BASE_URL=<URL>`; HTTPS certificates are verified. No numeric coverage threshold is configured; cover changed behavior and regressions.

## Commit & Pull Request Guidelines

Follow existing Conventional Commit patterns: `feat(builder): ...`, `fix: ...`, or `docs: ...`. Keep commits focused. PRs should explain behavior changes, link relevant issues or plan items, list validation results, and include screenshots for UI changes. Match CI formatting, analysis, tests, and platform builds before merging.

## Security & Configuration

Configure public settings through `APP_ENV` and `CRAFTAI_API_BASE_URL`. Keep credentials, signing material, and tokens out of source and logs; use secure storage and CI secrets.

## Token Efficiency

- Read only files relevant to the task.
- Batch independent file reads.
- Avoid repeatedly exploring the same code.
- Keep explanations concise.
- Do not produce lengthy plans for straightforward tasks.
- Prioritize implementation over unnecessary commentary.

