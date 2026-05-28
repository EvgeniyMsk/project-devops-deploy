# syntax=docker/dockerfile:1

# --- Frontend build ---
FROM node:20-alpine AS frontend-build
WORKDIR /build/frontend

COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

COPY frontend/ ./
RUN npm run build

# --- Backend build ---
FROM eclipse-temurin:21-jdk AS backend-build
WORKDIR /build

COPY gradlew gradlew.bat settings.gradle.kts build.gradle.kts versions.properties ./
COPY gradle/ gradle/
COPY src/ src/

COPY --from=frontend-build /build/frontend/dist/ src/main/resources/static/

RUN chmod +x gradlew \
    && ./gradlew bootJar -x test --no-daemon

# --- Runtime ---
FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app

RUN addgroup -g 1001 app && adduser -u 1001 -G app -D app

COPY --from=backend-build /build/build/libs/project-devops-deploy-*.jar app.jar

USER app

EXPOSE 8080 9090

ENV JAVA_OPTS=""

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
