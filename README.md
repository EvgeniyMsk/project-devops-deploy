# Project DevOps Deploy

![CI](https://github.com/EvgeniyMsk/project-devops-deploy/actions/workflows/ci.yml/badge.svg)

Bulletin board service: Spring Boot REST API, React Admin UI, image uploads (local filesystem or S3), and Spring Actuator for health and metrics.

> **Fork policy**: this upstream repository is read-only. We do not review or merge pull requests and we do not accept infrastructure changes (Dockerfiles, Ansible roles, CI/CD workflows, etc.). To experiment or extend the project, fork it and work inside your own repository.

The default `dev` profile uses an in-memory H2 database and seeds 10 sample bulletins through `DataInitializer`, so the API works immediately after startup.

API documentation is available via Swagger UI at `http://localhost:8080/swagger-ui/index.html`.

## CI/CD

GitHub Actions workflow [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every **push** and **pull request** to `main`.

Pipeline steps:

1. **Backend** — install Gradle dependencies, run tests, check code style (`spotlessCheck`).
2. **Frontend** — `npm ci`, production build.
3. **Docker** — build and push the image to the container registry **only after** backend and frontend jobs succeed, and **only on push to `main`** (not on pull requests).

### Image tagging

Each successful push to `main` publishes two tags:

| Tag | Example | Purpose |
|-----|---------|---------|
| `latest` | `cr.yandex/crpragsrepkuej79fefp/project-devops-deploy:latest` | always points to the last successful build |
| git SHA | `cr.yandex/crpragsrepkuej79fefp/project-devops-deploy:abc1234…` | immutable reference to a specific commit |

Use the SHA tag when you need to roll back or audit a deployment.

### Registry credentials (GitHub Secrets)

Do **not** commit tokens or passwords to the repository. Configure these secrets in the repository settings (`Settings → Secrets and variables → Actions`):

| Secret | Description |
|--------|-------------|
| `DOCKER_USERNAME` | Registry username (`oauth` for Yandex Container Registry) |
| `DOCKER_PASSWORD` | OAuth token or registry password |

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

All other variables supported by Spring Boot can be overridden the same way; check the application configuration files if you need to confirm a property name.

## Requirements

- JDK 21+.
- Gradle 9.2.1.
- PostgreSQL only if you run the `prod` profile with an external database.
- Make.
- NodeJS 20+

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

`JAVA_OPTS` can be used to control heap size, GC, or add any `-D` system properties without editing the manifest.

### Useful commands

See [Makefile](./Makefile)

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

Useful JVM options:

- `-Xms/-Xmx` — set memory limits inside the container.
- `-XX:+UseContainerSupport` / `-XX:ActiveProcessorCount` (these respect cgroup limits by default).
- `-Dspring.profiles.active=prod` — switch the profile without recompiling.
- `-Dlogging.level.root=INFO` or Spring environment variables (`SPRING_DATASOURCE_URL`, `STORAGE_S3_BUCKET`, etc.) — configure external services.

## Monitoring / management ports

- Application traffic still uses port `8080` by default. Actuator endpoints (health, metrics, Prometheus scrape, logfile) listen on `MANAGEMENT_SERVER_PORT` (defaults to `9090` for every profile). Override it via env vars when you need a different port.
- If your deployment does **not** include Prometheus/Grafana yet, you can ignore the management port entirely; the application starts normally even if nothing scrapes `/actuator`. Simply avoid publishing the management port in Docker/Kubernetes until you need it.
- When monitoring is enabled, expose both ports, e.g. `docker run -p 8080:8080 -p 9090:9090 ...` and point Prometheus to `http://<host>:9090/actuator/prometheus`.
- Health probes are available at `/actuator/health/liveness` and `/actuator/health/readiness`; Grafana/Loki integrations should use the same port/env variable.

## Actuator endpoints (local check)

With the app running locally (`make run`), the management port defaults to `http://localhost:9090`. Useful URLs:

- `http://localhost:9090/actuator` — index of exposed endpoints.
- `http://localhost:9090/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness` — readiness/liveness probes.
- `http://localhost:9090/actuator/metrics` and `http://localhost:9090/actuator/metrics/http.server.requests` — raw Micrometer metrics.
- `http://localhost:9090/actuator/prometheus` — Prometheus scrape output (open in browser or `curl` to confirm it renders).
- `http://localhost:9090/actuator/logfile` — current application log (same JSON that goes to stdout).

Override the host/port with `MANAGEMENT_SERVER_PORT` if you changed it; no Prometheus or Grafana instance is needed just to inspect these endpoints.

## Logging

- The backend ships with `src/main/resources/logback-spring.xml`, which writes structured JSON events to `stdout`. Every record contains `timestamp`, `app`, `environment`, `instance`, `logger`, `thread`, message arguments, MDC, and stack traces so Promtail/Loki (or any log shipper) can parse them without extra processing.
- No extra variables are required, but you can supply a different configuration via Spring Boot’s standard options (`LOGGING_CONFIG`, `logging.config`, or by overriding `logback-spring.xml` on the classpath).
- Container runtimes should forward `stdout`/`stderr` to your logging pipeline. Avoid redirecting logs to files unless your platform explicitly demands it.

## Image Upload Checks

### Local (dev profile, H2 + temp storage)

1. Start backend: `make run` (uses in-memory H2 and local filesystem storage under `/tmp/bulletin-images`).
2. Start frontend dev server: `cd frontend && npm install && npm run dev`.
3. In React Admin:
    - Create a bulletin or edit an existing one.
    - Use the “Upload image” field; after save, the image preview should load via the generated `imageUrl`.
4. Verify backend log: look for `Stored image` entries or check `/tmp/bulletin-images` for a new file. Refresh the bulletin show page to ensure the presigned/local URL still renders.

### Production / S3

1. Ensure the S3-related variables from the table above (bucket, region, access/secret keys, optional endpoint/CDN URL) are exported alongside the `prod` profile settings.
2. Deploy backend (e.g., `java -jar build/libs/project-devops-deploy-0.0.1-SNAPSHOT.jar`).
3. In the frontend (local or deployed), upload an image for a bulletin.
4. Confirm expected behavior:
    - Response from `/api/files/upload` contains a non-empty `key`.
    - Image shows up in bulletin show view (URL should either point to CDN or be a presigned S3 link).
    - Object exists in S3 bucket (check via AWS console or `aws s3 ls s3://your-bucket/bulletins/...`).
5. Optional: run `curl -I "$(curl -s .../api/files/view?key=... | jq -r .url)"` to ensure the presigned URL is valid from the production environment.
