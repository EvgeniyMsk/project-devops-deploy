# Project DevOps Deploy

![CI](https://github.com/EvgeniyMsk/project-devops-deploy/actions/workflows/ci.yml/badge.svg)

**Production:** [https://task.devops-campus.ru](https://task.devops-campus.ru)

- App UI and API: `https://task.devops-campus.ru/`
- Swagger UI: `https://task.devops-campus.ru/swagger-ui/index.html`
- Health check (internal): `http://127.0.0.1:9090/actuator/health` on the server

Bulletin board service: Spring Boot REST API, React Admin UI, image uploads (local filesystem or S3), and Spring Actuator for health and metrics.

> **Deployment** (Ansible, Nginx, Certbot, PostgreSQL on the server) lives in a separate repository:
> [devops-engineer-from-scratch-project-315](https://github.com/EvgeniyMsk/devops-engineer-from-scratch-project-315).

The default `dev` profile uses an in-memory H2 database and seeds 10 sample bulletins through `DataInitializer`, so the API works immediately after startup.

API documentation is available via Swagger UI at `http://localhost:8080/swagger-ui/index.html`.

## CI/CD

GitHub Actions workflow [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every **push** and **pull request** to `main`.

Pipeline steps:

1. **Backend** — install Gradle dependencies, run tests, check code style (`spotlessCheck`).
2. **Frontend** — `npm ci`, production build.
3. **Docker** — build and push the image to Yandex Container Registry **only after** backend and frontend jobs succeed, and **only on push to `main`** (not on pull requests).

### Image tagging

Each successful push to `main` publishes two tags:

| Tag | Example | Purpose |
|-----|---------|---------|
| `latest` | `cr.yandex/crpragsrepkuej79fefp/project-devops-deploy:latest` | always points to the last successful build |
| git SHA | `cr.yandex/crpragsrepkuej79fefp/project-devops-deploy:abc1234…` | immutable reference to a specific commit |

Use the SHA tag when you need to roll back or audit a deployment (redeploy from the Ansible repository).

### Если CI не запускается (fork)

Репозиторий — **fork**. GitHub по умолчанию **отключает Actions** в форках. Включите вручную:

1. Откройте [Settings → Actions → General](https://github.com/EvgeniyMsk/project-devops-deploy/settings/actions).
2. В разделе **Actions permissions** выберите **Allow all actions and reusable workflows**.
3. Нажмите **Save**.
4. Сделайте push в `main` или запустите workflow вручную: **Actions → CI → Run workflow**.

### Registry credentials (GitHub Secrets)

Do **not** commit tokens or passwords to the repository. Добавьте секреты в **Settings → Secrets and variables → Actions → Repository secrets**:

| Secret | Description |
|--------|-------------|
| `DOCKER_USERNAME` | Registry username (`oauth` for Yandex Container Registry) |
| `DOCKER_PASSWORD` | OAuth token for Yandex Container Registry (docker build/push) |

Local login example (replace `<YOUR_OAUTH_TOKEN>` with a token from Yandex Cloud):

```bash
echo "<YOUR_OAUTH_TOKEN>" | docker login \
  --username oauth \
  --password-stdin \
  cr.yandex

docker push cr.yandex/crpragsrepkuej79fefp/project-devops-deploy:latest
```

## Docker

The multi-stage `Dockerfile` builds the frontend, embeds it into the Spring Boot JAR, and packages a minimal JRE image.

After `make docker-build`, the expected artifact is a local Docker image:

- **Name:** `project-devops-deploy:latest` (override with `DOCKER_IMAGE` / `DOCKER_TAG`)

```bash
make docker-build   # build the image
make docker-run     # run the container (ports 8080 and 9090)
```

Or in one step: `make docker-start`.

- App UI and API: `http://localhost:8080/`
- Swagger UI: `http://localhost:8080/swagger-ui/index.html`
- Actuator: `http://localhost:9090/actuator/health`

The container starts with the `dev` profile by default (in-memory H2). For production, pass `JAVA_OPTS` and database/S3 variables (see [Running in Docker](#running-in-docker) below).

## Project layout

- Backend (Spring Boot) lives in the repository root.
- Frontend (React Admin + Vite) is located in `frontend/`.
- Shared static assets for the backend are served from `src/main/resources/static` (populated by the frontend build when needed).

Keep this structure in mind when running commands—backend tooling (`gradlew`, `make run`, tests) run from the root, frontend tooling (`npm`, `vite`) runs from `frontend/`.

## Environment variables

Key variables are read directly by Spring Boot (see `src/main/resources/application.yml` and `application-prod.yml` for defaults):

| Variable                     | Description                                                   | Default                                      |
|------------------------------|---------------------------------------------------------------|----------------------------------------------|
| `SPRING_PROFILES_ACTIVE`     | Active Spring profile (`dev`, `prod`, etc.)                   | `dev`                                        |
| `SPRING_DATASOURCE_URL`      | JDBC URL for PostgreSQL in `prod`                             | `jdbc:postgresql://localhost:5432/bulletins` |
| `SPRING_DATASOURCE_USERNAME` | DB username                                                   | `postgres`                                   |
| `SPRING_DATASOURCE_PASSWORD` | DB password                                                   | `postgres`                                   |
| `STORAGE_S3_BUCKET`          | Bucket name for bulletin images                               | empty                                        |
| `STORAGE_S3_REGION`          | Region for the S3-compatible storage                          | empty                                        |
| `STORAGE_S3_ENDPOINT`        | Optional custom endpoint                                      | empty                                        |
| `STORAGE_S3_ACCESSKEY`       | Access key ID                                                 | empty                                        |
| `STORAGE_S3_SECRETKEY`       | Secret key                                                    | empty                                        |
| `STORAGE_S3_CDNURL`          | Optional public CDN prefix                                    | empty                                        |
| `MANAGEMENT_SERVER_PORT`     | Port for Spring Actuator endpoints (health, metrics, etc.)    | `9090`                                       |
| `JAVA_OPTS`                  | Extra JVM parameters (heap, `-Dspring.profiles.active`, etc.) | empty                                        |

## Requirements

### Local development

- JDK 21+.
- Gradle 9.2.1.
- PostgreSQL only if you run the `prod` profile with an external database.
- Make.
- Node.js 20+.

## Running

### Backend (local dev profile)

1. Install prerequisites from the **Requirements** section.
2. From the repository root start the backend:

    ```bash
    make run
    ```

3. Explore the API:
   - `GET http://localhost:8080/api/bulletins`
   - `GET http://localhost:8080/api/bulletins?page=1&perPage=9&sort=createdAt&order=DESC&state=PUBLISHED&search=laptop`
   - Swagger UI: `http://localhost:8080/swagger-ui/index.html`

`/api/bulletins` accepts pagination (`page`, `perPage`), sorting (`sort`, `order`) and filters (`state`, `search`). Filters are processed via JPA Specifications so the same contract is available to the React Admin frontend.

### Frontend (development build)

1. Open a second terminal and move into the frontend directory:

    ```bash
    cd frontend
    make install   # npm install
    make start     # Vite dev server on http://localhost:5173
    ```

2. The dev server proxies `/api` requests to `http://localhost:8080`, so keep the backend running.

### Production profile on a single host

1. Export the environment variables from the table above (DB access, S3 storage, `JAVA_OPTS`, etc.). The defaults in `application-prod.yml` show the exact property names if you need to double-check.
2. Build and launch the backend:

    ```bash
    make build
    java -jar build/libs/project-devops-deploy-0.0.1-SNAPSHOT.jar
    ```

3. Serve the frontend either from the same JVM (see **Build and serve from the Java app**) or deploy it separately (any static hosting/CDN works once `frontend/dist` is uploaded).

### Makefile reference

| Command | Description |
|---------|-------------|
| `make run` | Start backend locally (dev profile, H2) |
| `make test` | Run backend tests |
| `make build` | Build JAR |
| `make lint` / `make lint-fix` | Code style check / auto-fix |
| `make docker-build` | Build local Docker image |
| `make docker-run` | Run local Docker container |

## Frontend

### Development

1. Install Node.js 24 LTS (or newer) and npm.
2. Install dependencies and start the Vite dev server:

    ```bash
    cd frontend
    make install
    make start
    ```

3. The dev server proxies `/api` requests to `http://localhost:8080`, so keep the backend running via `make run` (or `./gradlew bootRun`) in another terminal.

### Image upload flow

1. Upload files via `POST /api/files/upload` (multipart form field named `file`).
2. The response contains `key` and a temporary `url`. Persist the `key` in the `imageKey` field when creating or updating bulletins; the backend stores only that identifier.
3. When you need a fresh link, call `GET /api/files/view?key=...` to receive a new URL (the backend issues presigned links on demand).

### Build and serve from the Java app

1. Build the production bundle:

    ```bash
    cd frontend
    make install      # run once
    make build    # outputs to frontend/dist
    ```

2. Copy the compiled assets into Spring Boot’s static resources (served from `src/main/resources/static`):

    ```bash
    rm -rf src/main/resources/static
    mkdir -p src/main/resources/static
    cp -R frontend/dist/* src/main/resources/static/
    ```

3. Restart the backend (`make run`) and open `http://localhost:8080/` — the React app will now be served directly by the Java application.

### Running in Docker

Build and run via Makefile (see [Docker](#docker)), or pass JVM flags via `JAVA_OPTS`:

```bash
docker run --rm -p 8080:8080 -p 9090:9090 \
  -e JAVA_OPTS="-Xms256m -Xmx512m -Dspring.profiles.active=prod" \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://host.docker.internal:5432/bulletins \
  project-devops-deploy:latest
```

## Monitoring / management ports

- Application traffic still uses port `8080` by default. Actuator endpoints (health, metrics, Prometheus scrape, logfile) listen on `MANAGEMENT_SERVER_PORT` (defaults to `9090` for every profile).
- Health probes are available at `/actuator/health/liveness` and `/actuator/health/readiness`.

## Actuator endpoints (local check)

With the app running locally (`make run`), the management port defaults to `http://localhost:9090`. Useful URLs:

- `http://localhost:9090/actuator` — index of exposed endpoints.
- `http://localhost:9090/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness` — readiness/liveness probes.
- `http://localhost:9090/actuator/metrics` and `http://localhost:9090/actuator/prometheus` — metrics.

## Logging

- The backend ships with `src/main/resources/logback-spring.xml`, which writes structured JSON events.
- **dev profile** — logs go to `stdout` only.
- **prod profile** — logs go to `stdout` and `/app/logs/application.log` (host path: `/var/log/bulletins`, bind-mounted in Docker).

## Image Upload Checks

### Local (dev profile, H2 + temp storage)

1. Start backend: `make run` (uses in-memory H2 and local filesystem storage under `/tmp/bulletin-images`).
2. Start frontend dev server: `cd frontend && npm install && npm run dev`.
3. In React Admin, create or edit a bulletin and upload an image.

### Production / S3

Production deployment and S3 configuration are managed via the [Ansible repository](https://github.com/EvgeniyMsk/devops-engineer-from-scratch-project-315). After deploy, verify uploads at [https://task.devops-campus.ru](https://task.devops-campus.ru).
