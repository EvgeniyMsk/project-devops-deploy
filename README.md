# Project DevOps Deploy

![CI](https://github.com/EvgeniyMsk/project-devops-deploy/actions/workflows/ci.yml/badge.svg)

**Production:** [https://task.devops-campus.ru](https://task.devops-campus.ru)

- App UI and API: `https://task.devops-campus.ru/`
- Swagger UI: `https://task.devops-campus.ru/swagger-ui/index.html`
- Health check (internal): `http://127.0.0.1:9090/actuator/health` on the server

Bulletin board service: Spring Boot REST API, React Admin UI, image uploads (local filesystem or S3), and Spring Actuator for health and metrics.

## Репозитории

| Репозиторий | Содержимое |
|-------------|------------|
| **[project-devops-deploy](https://github.com/EvgeniyMsk/project-devops-deploy)** (этот) | Код приложения, `Dockerfile`, CI (тесты + сборка/push образа) |
| **[devops-engineer-from-scratch-project-315](https://github.com/EvgeniyMsk/devops-engineer-from-scratch-project-315)** | Только Ansible: сервер, Nginx, Certbot, PostgreSQL, деплой |

Деплой на production выполняется **из Ansible-репозитория** (`make deploy`), не из этого.

The default `dev` profile uses an in-memory H2 database and seeds 10 sample bulletins through `DataInitializer`, so the API works immediately after startup.

API documentation: `http://localhost:8080/swagger-ui/index.html`

## CI/CD

Workflow [`.github/workflows/ci.yml`](.github/workflows/ci.yml) запускается при **push** и **pull_request** в `main`, а также вручную (**workflow_dispatch**).

| Job | Когда | Что делает |
|-----|-------|------------|
| `backend` | push, PR, manual | `make lint`, `make test` |
| `frontend` | push, PR, manual | `npm ci`, `npm run lint`, `npm run build` |
| `docker` | push в `main`, manual | Сборка и push образа в Yandex Container Registry |

Job `docker` использует environment **`production`** и секреты `DOCKER_USERNAME` / `DOCKER_PASSWORD`.

### Образ в registry

```
cr.yandex/crpd2isbgl7k3puo75s1/project-devops-deploy
```

| Tag | Назначение |
|-----|------------|
| `latest` | Последняя успешная сборка из `main` |
| `<git-sha>` | Неизменяемая ссылка на конкретный коммит (для отката) |

Откат на сервере: `make deploy ANSIBLE_DOCKER_TAG=<git-sha>` в Ansible-репозитории.

### Если CI не запускается (fork)

Репозиторий — **fork**. GitHub по умолчанию отключает Actions:

1. [Settings → Actions → General](https://github.com/EvgeniyMsk/project-devops-deploy/settings/actions)
2. **Allow all actions and reusable workflows** → Save
3. Push в `main` или **Actions → CI → Run workflow**

### Секреты GitHub

**Settings → Environments → production → Environment secrets:**

| Secret | Значение |
|--------|----------|
| `DOCKER_USERNAME` | `oauth` |
| `DOCKER_PASSWORD` | OAuth-токен Yandex Cloud для Container Registry |

## Docker

Multi-stage `Dockerfile`: frontend → Spring Boot JAR → JRE Alpine.

```bash
make docker-build   # локальный образ project-devops-deploy:latest
make docker-run     # порты 8080 и 9090
make docker-start   # build + run
```

По умолчанию контейнер стартует с профилем `dev` (H2). Для prod передайте `JAVA_OPTS` и переменные БД/S3.

## Структура проекта

```
project-devops-deploy/
├── src/                  # Spring Boot backend
├── frontend/             # React Admin + Vite
├── Dockerfile
├── Makefile
└── .github/workflows/ci.yml
```

Команды backend — из корня (`make run`, `make test`). Frontend — из `frontend/` (`npm run dev`).

## Переменные окружения

| Variable | Description | Default |
|----------|-------------|---------|
| `SPRING_PROFILES_ACTIVE` | Spring profile | `dev` |
| `SPRING_DATASOURCE_URL` | JDBC URL (prod) | `jdbc:postgresql://localhost:5432/bulletins` |
| `SPRING_DATASOURCE_USERNAME` | DB user | `postgres` |
| `SPRING_DATASOURCE_PASSWORD` | DB password | `postgres` |
| `STORAGE_S3_BUCKET` | S3 bucket | empty |
| `STORAGE_S3_REGION` | S3 region | empty |
| `STORAGE_S3_ENDPOINT` | S3 endpoint | empty |
| `STORAGE_S3_ACCESSKEY` | Access key | empty |
| `STORAGE_S3_SECRETKEY` | Secret key | empty |
| `MANAGEMENT_SERVER_PORT` | Actuator port | `9090` |
| `JAVA_OPTS` | JVM flags | empty |

Подробнее: `src/main/resources/application.yml`, `application-prod.yml`.

## Локальная разработка

### Требования

- JDK 21+
- Gradle 9.2.1 (wrapper в репозитории)
- Node.js 20+ (CI использует 24)
- Make

### Backend

```bash
make run
```

- `GET http://localhost:8080/api/bulletins`
- Swagger: `http://localhost:8080/swagger-ui/index.html`

### Frontend

```bash
cd frontend
npm install
npm run dev    # http://localhost:5173, прокси /api → :8080
```

### Makefile

| Command | Description |
|---------|-------------|
| `make run` | Backend (dev, H2) |
| `make test` | Тесты |
| `make build` | Сборка JAR |
| `make lint` / `make lint-fix` | Spotless |
| `make docker-build` | Локальный Docker-образ |
| `make docker-run` | Запуск контейнера |

## Frontend

### Загрузка изображений

1. `POST /api/files/upload` (поле `file`)
2. Сохранить `key` в `imageKey` объявления
3. `GET /api/files/view?key=...` — получить URL

### Сборка в JAR

```bash
cd frontend && npm run build
rm -rf ../src/main/resources/static
mkdir -p ../src/main/resources/static
cp -R dist/* ../src/main/resources/static/
```

## Actuator

Порт `9090` (по умолчанию):

- `/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness`
- `/actuator/metrics`, `/actuator/prometheus`

## Production

Развёртывание, Nginx, TLS, PostgreSQL и S3 настраиваются в [Ansible-репозитории](https://github.com/EvgeniyMsk/devops-engineer-from-scratch-project-315).

После деплоя проверьте: [https://task.devops-campus.ru](https://task.devops-campus.ru)
