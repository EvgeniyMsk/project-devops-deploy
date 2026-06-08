# Project DevOps Deploy

![CI](https://github.com/EvgeniyMsk/project-devops-deploy/actions/workflows/ci.yml/badge.svg)

**Production:** [https://task.devops-campus.ru](https://task.devops-campus.ru)

- App UI and API: `https://task.devops-campus.ru/`
- Swagger UI: `https://task.devops-campus.ru/swagger-ui/index.html`
- Health check (internal): `http://127.0.0.1:9090/actuator/health` on the server

Bulletin board service: Spring Boot REST API, React Admin UI, image uploads (local filesystem or S3), and Spring Actuator for health and metrics.

> **Fork policy**: this upstream repository is read-only. We do not review or merge pull requests and we do not accept infrastructure changes (Dockerfiles, Ansible roles, CI/CD workflows, etc.). To experiment or extend the project, fork it and work inside your own repository.

The default `dev` profile uses an in-memory H2 database and seeds 10 sample bulletins through `DataInitializer`, so the API works immediately after startup.

API documentation is available via Swagger UI at `http://localhost:8080/swagger-ui/index.html`.

## CI/CD

GitHub Actions workflow [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every **push** and **pull request** to `main`.

Pipeline steps:

1. **Backend** — install Gradle dependencies, run tests, check code style (`spotlessCheck`).
2. **Frontend** — `npm ci`, production build.
3. **Docker** — build and push the image to Yandex Container Registry **only after** backend and frontend jobs succeed, and **only on push to `main`** (not on pull requests).
4. **Deploy** — run `make deploy` via Ansible on the production server (only on push to `main`).

### Image tagging

Each successful push to `main` publishes two tags:

| Tag | Example | Purpose |
|-----|---------|---------|
| `latest` | `cr.yandex/crpragsrepkuej79fefp/project-devops-deploy:latest` | always points to the last successful build |
| git SHA | `cr.yandex/crpragsrepkuej79fefp/project-devops-deploy:abc1234…` | immutable reference to a specific commit |

Use the SHA tag when you need to roll back or audit a deployment.

### Rollback on the server

CI publishes an immutable image tag for every commit (`<git-sha>`). To roll back production to a known-good build, redeploy with that tag:

```bash
export SPRING_DATASOURCE_USERNAME=...
export SPRING_DATASOURCE_PASSWORD=...
export STORAGE_S3_ACCESSKEY=...
export STORAGE_S3_SECRETKEY=...
export DOCKER_OAUTH_TOKEN=...
export ANSIBLE_PASSWORD=...
make deploy ANSIBLE_DOCKER_TAG=<git-sha>
```

The default tag is `latest`. Image tag is configured in `inventory/group_vars/web_servers.yml` (`docker_tag`) and can be overridden at deploy time via `ANSIBLE_DOCKER_TAG`.

### How image updates work on the server

On every `make deploy` Ansible:

1. Logs in to Yandex Container Registry.
2. Pulls `{{ docker_image }}:{{ docker_tag }}` with `force_source: true` (always checks the registry manifest, even if a local image exists).
3. Recreates the `application` container with `pull: always` and `recreate: true`.
4. Extracts frontend static files from the new image into `/var/www/bulletins`.

Docker compares image **digests** in the registry with the local copy. If CI pushed a new `latest`, the server downloads new layers; if the digest is unchanged, the pull is a no-op. There is no separate version check — the registry is the source of truth.

In the Ansible output, look at **Pull application image from registry**: `changed: true` means a new image was downloaded.

### Registry credentials (GitHub Secrets)

Do **not** commit tokens or passwords to the repository. Configure these secrets in the **production** environment (`Settings → Environments → production → Environment secrets`):

| Secret | Description |
|--------|-------------|
| `DOCKER_USERNAME` | Registry username (`oauth` for Yandex Container Registry) |
| `DOCKER_PASSWORD` | OAuth token for Yandex Container Registry (docker build/push) |
| `DOCKER_OAUTH_TOKEN` | Same OAuth token for Ansible deploy (`docker login` on server) |
| `ANSIBLE_PASSWORD` | SSH password for the production server |
| `SPRING_DATASOURCE_USERNAME` | PostgreSQL username |
| `SPRING_DATASOURCE_PASSWORD` | PostgreSQL password |
| `STORAGE_S3_ACCESSKEY` | Yandex Object Storage access key |
| `STORAGE_S3_SECRETKEY` | Yandex Object Storage secret key |

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
- Ansible deployment: `playbook.yml`, `inventory/`, `templates/`.

Keep this structure in mind when running commands—backend tooling (`gradlew`, `make run`, tests) run from the root, frontend tooling (`npm`, `vite`) runs from `frontend/`.

## Production architecture

```text
Internet
   │
   ▼
Nginx (:80 / :443)          task.devops-campus.ru
   │  static: /var/www/bulletins
   │  proxy: 127.0.0.1:8080
   ▼
application (Docker)        Spring Boot, prod profile
   │  logs: /var/log/bulletins
   ▼
database (postgres:14)      PostgreSQL, data: /var/lib/postgresql/bulletins
   │
   ▼
Yandex Object Storage       bulletin images (S3-compatible)
```

| Component | Details |
|-----------|---------|
| Reverse proxy | Nginx (`geerlingguy.nginx`), TLS via Certbot (`webroot` mode) |
| Application | `cr.yandex/crpragsrepkuej79fefp/project-devops-deploy:latest` |
| Database | `postgres:14`, host volume owned by UID 999 |
| Secrets | GitHub Environment secrets → env vars → Ansible extra vars (`-e`) |
| Public vars | `inventory/group_vars/web_servers.yml`: domain, bucket, image tag |
| Inventory | `inventory/inventory.ini`: server IP, SSH user (key-based auth) |

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

### Local development (control machine)

- JDK 21+.
- Gradle 9.2.1.
- PostgreSQL only if you run the `prod` profile with an external database.
- Make.
- Node.js 20+.

### Production deployment

**Control node** (where you run Ansible from your laptop or CI):

- Python 3.12+ and Ansible (`pip install ansible`).
- SSH key access to the target server (passwords are not stored in the repository).
- Environment variables with deploy secrets (see table below).
- `make galaxy` installs roles from `requirements.yml` before the first run.

**Target server** (`task.devops-campus.ru`, Ubuntu):

- Ubuntu 22.04 or newer, SSH on port 22 (user `root` or another sudo-capable user).
- At least 2 GB RAM and 10 GB free disk.
- Public ports 80 and 443 (Nginx + Certbot); application ports 8080/9090 bound to `127.0.0.1`.
- DNS A-record for `task.devops-campus.ru` pointing to the server IP.
- Persistent host paths:
  - `/var/lib/postgresql/bulletins` — PostgreSQL 14 data (owner UID 999)
  - `/var/log/bulletins` — application logs
  - `/var/www/bulletins` — frontend static files served by Nginx
  - `/var/www/letsencrypt` — Certbot webroot for ACME challenges

### Ansible configuration

| File | Purpose |
|------|---------|
| `playbook.yml` | Server setup and deploy (Docker, UFW, Nginx, Certbot, PostgreSQL, app) |
| `inventory/inventory.ini` | Target host (`main`) and SSH settings |
| `inventory/group_vars/web_servers.yml` | Non-secret vars: domain, S3 bucket, image tag, paths |
| `requirements.yml` | Ansible roles (`geerlingguy.nginx`, `geerlingguy.certbot`) and `community.docker` |
| `templates/nginx-bulletins*.j2` | Nginx reverse proxy, caching, HTTPS |

Deploy secrets are passed as environment variables and forwarded to Ansible via `make deploy` / `make setup`:

| Environment variable | Ansible variable |
|---------------------|------------------|
| `SPRING_DATASOURCE_USERNAME` | `spring_datasource_username` |
| `SPRING_DATASOURCE_PASSWORD` | `spring_datasource_password` |
| `STORAGE_S3_ACCESSKEY` | `storage_s3_accesskey` |
| `STORAGE_S3_SECRETKEY` | `storage_s3_secretkey` |
| `DOCKER_OAUTH_TOKEN` | `docker_oauth_token` |
| `ANSIBLE_PASSWORD` | `ansible_password` (SSH) |

Local deploy example:

```bash
export SPRING_DATASOURCE_USERNAME=postgres
export SPRING_DATASOURCE_PASSWORD=...
export STORAGE_S3_ACCESSKEY=...
export STORAGE_S3_SECRETKEY=...
export DOCKER_OAUTH_TOKEN=...
export ANSIBLE_PASSWORD=...
make deploy
```

### Ansible commands

```bash
# Install Ansible roles and collections (once, or before each run)
make galaxy

# First-time server preparation (Docker, UFW, Nginx, Certbot, PostgreSQL, app)
make setup

# Deploy or update application + Nginx + Certbot (pulls fresh image, recreates containers)
make deploy

# Roll back to a specific image build
make deploy ANSIBLE_DOCKER_TAG=<git-sha>
```

`make deploy` runs tags `deploy,certbot,nginx`: updates Docker containers, renews/obtains TLS certificates, and restarts Nginx.

### Production verification

```bash
# On the server
docker ps
docker logs application --tail 30
docker logs database --tail 10
ss -tlnp | grep -E ':80|:443'
certbot certificates
curl -s http://127.0.0.1:8080/api/bulletins
curl -I https://task.devops-campus.ru
```

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

### Makefile reference

| Command | Description |
|---------|-------------|
| `make run` | Start backend locally (dev profile, H2) |
| `make test` | Run backend tests |
| `make build` | Build JAR |
| `make lint` / `make lint-fix` | Code style check / auto-fix |
| `make docker-build` | Build local Docker image |
| `make docker-run` | Run local Docker container |
| `make galaxy` | Install Ansible roles from `requirements.yml` |
| `make setup` | Full server provisioning (first run) |
| `make deploy` | Update application on production server |

Deploy variables: `ANSIBLE_DOCKER_TAG` (default: `latest`) and secret env vars listed above.

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

- The backend ships with `src/main/resources/logback-spring.xml`, which writes structured JSON events.
- **dev profile** — logs go to `stdout` only.
- **prod profile** — logs go to `stdout` and `/app/logs/application.log` (host path: `/var/log/bulletins`, bind-mounted in Docker).
- Every record contains `timestamp`, `app`, `environment`, `instance`, `logger`, `thread`, message arguments, MDC, and stack traces so Promtail/Loki (or any log shipper) can parse them without extra processing.
- Override via Spring Boot options (`LOGGING_CONFIG`, `logging.config`) or by replacing `logback-spring.xml` on the classpath.

## Image Upload Checks

### Local (dev profile, H2 + temp storage)

1. Start backend: `make run` (uses in-memory H2 and local filesystem storage under `/tmp/bulletin-images`).
2. Start frontend dev server: `cd frontend && npm install && npm run dev`.
3. In React Admin:
    - Create a bulletin or edit an existing one.
    - Use the “Upload image” field; after save, the image preview should load via the generated `imageUrl`.
4. Verify backend log: look for `Stored image` entries or check `/tmp/bulletin-images` for a new file. Refresh the bulletin show page to ensure the presigned/local URL still renders.

### Production / S3

#### S3 bucket setup

Production uses Yandex Object Storage. Create a bucket and service-account keys manually before the first deploy:

1. Follow the [Yandex Cloud guide: create an Object Storage bucket](https://yandex.cloud/ru/docs/storage/operations/buckets/create).
2. Create a service account with minimally required permissions (`storage.editor` or scoped read/write on the bucket).
3. Generate an Access Key / Secret Key pair and store them in GitHub Environment secrets (`STORAGE_S3_ACCESSKEY`, `STORAGE_S3_SECRETKEY`).
4. Set non-secret parameters in `inventory/group_vars/web_servers.yml`: `storage_s3_bucket`, `storage_s3_region`, `storage_s3_endpoint`.

#### Verify uploads

1. Ensure the S3-related variables from the table above (bucket, region, access/secret keys, optional endpoint/CDN URL) are exported alongside the `prod` profile settings.
2. Deploy backend (e.g., `make deploy` or `java -jar build/libs/project-devops-deploy-0.0.1-SNAPSHOT.jar`).
3. Open [https://task.devops-campus.ru](https://task.devops-campus.ru) and upload an image for a bulletin.
4. Confirm expected behavior:
    - Response from `/api/files/upload` contains a non-empty `key`.
    - Image shows up in bulletin show view (URL should either point to CDN or be a presigned S3 link).
    - Object exists in S3 bucket (check via Yandex Cloud console or `aws s3 ls s3://your-bucket/bulletins/...`).
5. Optional: run `curl -I "$(curl -s .../api/files/view?key=... | jq -r .url)"` to ensure the presigned URL is valid from the production environment.
