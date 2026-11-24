# Публикация Craftai Lab в интернете

Проект состоит из Flutter Web (`Builder/`), FastAPI (`backend/`), PostgreSQL
и каталога загруженных файлов. Статический хостинг публикует только Flutter;
для авторизации, агентов и моделей нужен отдельно доступный HTTPS API.

На 21.11.2026 существующие `https://takarka.github.io/craftai-lab/` и
`https://craftai-lab-api.onrender.com/health` вернули HTTP 200. Это проверка
доступности, не проверка текущей опубликованной версии или полного сценария работы.

## Варианты размещения

| Вариант | Что размещаем | Когда выбирать |
| --- | --- | --- |
| GitHub Pages + Render + PostgreSQL | Web через Actions, API в Docker, файлы на диске Render | Минимум изменений: эти адреса уже указаны в README; workflow подготовлен |
| Cloudflare Pages + Render + PostgreSQL | Готовую папку `Builder/build/web` загружаем в Pages | Альтернативный хостинг интерфейса и собственный домен |
| Firebase Hosting + отдельный API/PostgreSQL | Flutter как статический сайт с HTTPS | Если уже используется Firebase; FastAPI отдельно |
| VPS + Docker Compose + Caddy/nginx | Web, API, PostgreSQL и том файлов на сервере | Полный контроль, но обновления, TLS, мониторинг и резервные копии обслуживаем самостоятельно |

Рекомендация для первой рабочей публикации — GitHub Pages + Render.
Это выбор по существующей конфигурации проекта, не результат нагрузочного теста.
Бесплатный Render подходит для временного демо: API засыпает после 15 минут
простоя, локальные файлы теряются при перезапуске, бесплатный PostgreSQL
истекает через 30 дней. Для постоянной работы нужны постоянная БД и файловый диск.

**`render.yaml` сохраняет текущий бесплатный тариф без постоянного диска.**
Для текущей демонстрации достаточно существующей ссылки; ручной workflow
не запускается от push. Подключённый Render может автоматически пересобрать API
после push в `main`, сохраняя бесплатный тариф.

**Отдельный `render.production.yaml` описывает платный план Starter и диск 1 ГБ.**
Он предназначен для последующего явного выбора в Render и не заменяет основной
Blueprint. Его применение может создать расходы: отдельно API, диск, PostgreSQL
и вызовы моделей.
Действующие цены проверьте в панели перед применением.

## 1. Подготовить API

1. Создать постоянную PostgreSQL или использовать существующую. Если в старом
   API есть данные, сначала сделать резервную копию БД и файлов и выполнить
   перенос по [backend/PERSISTENCE.md](../backend/PERSISTENCE.md).
2. Для постоянного размещения в Render подключить репозиторий, явно выбрать
   Blueprint `render.production.yaml` из ветки
   с этими изменениями. В файле отслеживается `main`; если используется другая
   ветка, изменить `branch` до применения. Существующий сервис сначала сверить
   с Blueprint, чтобы не создать второй API случайно.
3. Указать `CRAFTAI_DATABASE_URL` (URL PostgreSQL от провайдера),
   `CRAFTAI_OPENROUTER_API_KEY` и хотя бы один реальный ID модели:
   `CRAFTAI_LAB_MODEL_1_ID` или `CRAFTAI_LAB_MODEL_2_ID`.
   Для полного сценария PRD с двумя моделями заполнить оба слота разными ID.
   Включать `CRAFTAI_LAB_MODEL_*_SUPPORTS_TOOLS`/`SUPPORTS_VISION`
   только после проверки возможностей выбранных моделей.
   Без настроенного каталога запуски моделей недоступны.
   Эти переменные нужны и для бесплатного сервиса из `render.yaml`.
   В существующем сервисе открыть **Environment**, заполнить хотя бы один
   `CRAFTAI_LAB_MODEL_1_ID` или `CRAFTAI_LAB_MODEL_2_ID` реальным ID OpenRouter,
   сохранить настройки и выполнить redeploy. Один API-ключ каталог не заполняет.
   После входа проверить `GET /lab/v1/models`: хотя бы одна запись должна иметь
   `available: true` и непустой `model_id`. Агент без выбранной модели использует
   первый доступный слот автоматически; пересоздавать агента не требуется.
   На старых версиях API отсутствие и выбранной модели, и настроенных слотов
   возвращает `422 model.not-selected`; исправленная версия возвращает
   `503 model.not-configured` с сообщением о настройке сервера.
4. Для нового сервиса Blueprint генерирует JWT-секрет. Для существующего
   сохранить текущий секрет, иначе пользователям придётся войти заново.
5. Проверить диск `/var/data` и `CRAFTAI_STORAGE_DIR=/var/data/storage`.
   Старые файлы переносить отдельно: новая точка монтирования сама их не копирует.
6. `CRAFTAI_CORS_ORIGINS` должен содержать JSON-массив точных origin интерфейса:
   `["https://takarka.github.io"]`. Путь `/craftai-lab/` и завершающий `/`
   не добавлять. Для другого домена изменить значение, например
   `["https://lab.example.com"]`. CORS ограничивает браузеры и не заменяет авторизацию.
   По умолчанию код также разрешает текущий `https://takarka.github.io`
   и локальные порты 3000/8080, чтобы обновление API не отключило текущую Web-версию.
7. Дождаться `GET https://<api-host>/health` → HTTP 200,
   `{"status":"healthy"}`. Миграции выполняются при старте API;
   `/health` подтверждает запуск, но не доступность OpenRouter.

Хранить секреты только в настройках сервера. `--dart-define` включается
в общедоступную сборку и подходит только для публичного URL API.
Диск Render предполагает один экземпляр API; горизонтальное масштабирование
потребует общего файлового хранилища и отдельного решения для фоновой работы.

### Создать PostgreSQL и задать переменные в Render

1. Открыть [New Postgres](https://dashboard.render.com/new/database).
   Указать Name `craftai-lab-db`, Database `craftai_lab`, PostgreSQL Version `16`.
   User можно оставить автоматически созданным. Region должен совпадать с
   регионом сервиса `craftai-lab-api` в том же аккаунте.
2. Выбрать тариф и нажать **Create database**. Free подходит для временного
   демо, но база истекает через 30 дней; для постоянной работы выбрать платный
   тариф. Дождаться статуса **Available**.
3. Открыть **Connect** у созданной базы и скопировать **Internal Database URL**.
   Если нужно сохранить прежние данные SQLite, сначала выполнить перенос по
   [backend/PERSISTENCE.md](../backend/PERSISTENCE.md): новая база будет пустой.
4. Открыть **craftai-lab-api → Environment → Add Environment Variable**.
   Задать значения без кавычек:

   | Key | Value |
   | --- | --- |
   | `CRAFTAI_DATABASE_URL` | Полный Internal Database URL из шага 3 |
   | `CRAFTAI_OPENROUTER_API_KEY` | Собственный ключ OpenRouter |
   | `CRAFTAI_LAB_MODEL_1_ID` | Реальный ID модели OpenRouter |
   | `CRAFTAI_LAB_MODEL_1_SUPPORTS_TOOLS` | `true`, если модель поддерживает инструменты; иначе `false` |
   | `CRAFTAI_LAB_MODEL_1_SUPPORTS_VISION` | `true`, если модель поддерживает изображения; иначе `false` |

5. Нажать **Save and deploy**, дождаться запуска API и проверить каталог моделей
   по инструкции выше. URL вида `postgres://` или `postgresql://` приложение
   преобразует в нужный формат автоматически. Переменная `DATABASE_URL` без
   префикса `CRAFTAI_` не заменяет `CRAFTAI_DATABASE_URL`.

Ошибка `Set CRAFTAI_DATABASE_URL to PostgreSQL outside dev/test` означает,
что API не получил URL PostgreSQL и пытается использовать SQLite. В production
такая конфигурация блокирует запуск.

Справка Render: [создание и подключение PostgreSQL](https://render.com/docs/postgresql-creating-connecting),
[переменные окружения](https://render.com/docs/configure-environment-variables),
[ограничения Free](https://render.com/docs/free).

## 2. Опубликовать Web на GitHub Pages

1. Отправить подготовленные изменения в GitHub.
2. В репозитории открыть **Settings → Pages → Source → GitHub Actions**.
3. Открыть **Actions → Publish web to GitHub Pages → Run workflow**.
   Workflow должен находиться в default branch, чтобы появился ручной запуск.
4. Выбрать ветку с нужным кодом и указать действующий HTTPS URL API.
5. Сборка проверит `/health`, выполнит `flutter analyze`, соберёт `lib/main.dart`
   в production и опубликует артефакт Pages. Ссылку выдаст job `deploy`.

Workflow запускается только вручную. Он не содержит ключей облачных провайдеров:
для Pages используется временный `GITHUB_TOKEN` с правами в job публикации.
Полный тестовый набор остаётся в существующих CI workflows.
Перед выпуском проверить их успешное завершение для выбранной версии.

Для `takarka/craftai-lab` ожидаемый адрес —
`https://takarka.github.io/craftai-lab/`. В сборку подставляется
`--base-href /craftai-lab/`; для репозитория `<owner>.github.io` используется `/`.
Для собственного домена в корне сайта нужно изменить base href на `/`
и настроить домен в Pages/DNS. Роутинг проекта использует стандартные hash URL;
не включать path URL без настройки fallback на `index.html`.

## 3. Сборка для другого статического хостинга

Из `Builder/`, используя Flutter из `.fvmrc`:

```powershell
flutter pub get --enforce-lockfile
flutter build web --release --base-href / --dart-define=APP_ENV=prod --dart-define=CRAFTAI_API_BASE_URL=https://YOUR-API-HOST
```

Размещать содержимое `Builder/build/web`, а не исходники.
В Cloudflare Pages доступен Direct Upload готовой папки через Wrangler.
В Firebase Hosting указать public directory `build/web` и затем выполнить
`firebase deploy --only hosting`. Перед публикацией на новом адресе
добавить его origin в настройки API.

Для локальной проверки с новым CORS использовать фиксированный порт:

```powershell
flutter run -d chrome --web-port 8080 --dart-define=APP_ENV=dev --dart-define=CRAFTAI_API_BASE_URL=http://localhost:5001
```

При другом порте добавить соответствующий origin в `CRAFTAI_CORS_ORIGINS`.

## Проверка после публикации

- Открыть ссылку в приватном окне, зарегистрироваться и войти новой учётной записью.
- Создать агента, выполнить реальный запрос к модели, проверить поток ответа.
- Загрузить материал/фото, перезагрузить страницу и повторно войти.
- Перезапустить API и убедиться, что агент, прогресс и файлы сохранились.
- Проверить восстановление резервной копии PostgreSQL и файлов; постоянный диск
  сам по себе не заменяет резервное копирование.

## Официальная документация

Проверено 21.11.2026:

- [GitHub Pages: custom workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- [Render: ограничения бесплатных ресурсов](https://render.com/docs/free)
- [Render: постоянные диски](https://render.com/docs/disks)
- [Render: цены](https://render.com/pricing)
- [Cloudflare Pages: Direct Upload](https://developers.cloudflare.com/pages/get-started/direct-upload/)
- [Firebase Hosting: начало работы](https://firebase.google.com/docs/hosting/quickstart)
