# syntax=docker/dockerfile:1
# =============================================================================
# Multi-stage Dockerfile for the Tasks API (PRD §12).
#
# IMPORTANT: build this with the repository ROOT as the build context, so the
# build stage can see the Maven sources, and target linux/amd64 (the EC2 + CI
# architecture; the runtime base below has no arm64 variant):
#     docker build --platform linux/amd64 -f docker/Dockerfile -t tasks-api .
# (The .dockerignore lives at the repo root for the same reason.)
#
# "Multi-stage" means we use a big image with Maven + JDK to COMPILE, then copy
# only the finished jar into a small JRE image to RUN. The Maven layer (and the
# whole source tree) never ships in the final image.
# =============================================================================

# ---- build stage: compile and package the shaded jar ------------------------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /src
COPY . .
# Build only the app module and its dependencies; skip tests (CI runs them).
RUN mvn -q -pl app -am -DskipTests package

# ---- runtime stage: small image that just runs the jar ----------------------
# Alpine-based JRE keeps the final image well under the ~250 MB target (FR-DK-4).
# The app is pure Java (no native libraries), so musl libc is a non-issue.
FROM eclipse-temurin:17-jre-alpine AS runtime

# curl: used by the container HEALTHCHECK below (busybox has wget, but curl is
# clearer and matches the smoke-test script).
RUN apk add --no-cache curl \
    && adduser -D -u 10001 appuser  # non-root user (FR-DK-2)

WORKDIR /app
# The shaded (fat) jar carries its version in its name, so the glob resolves it.
COPY --from=build /src/app/target/*-shaded.jar app.jar

# Image metadata (FR-DK-4). CI/CD passes these; they default to dev locally.
ARG APP_VERSION=dev
ARG GIT_COMMIT=unknown
LABEL org.opencontainers.image.title="tasks-api" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}"

# /health reports this value; CD sets it to the git SHA of the deployed build.
ENV APP_VERSION=${APP_VERSION}

EXPOSE 8080
USER appuser

# The orchestrator marks the container unhealthy if /health stops returning 200.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -fsS http://localhost:8080/health || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
