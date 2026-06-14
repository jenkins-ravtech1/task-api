# Tasks API

A small, **plain-Java** HTTP API for managing tasks. It is the reference
implementation for an 8-session Cloud/DevOps course: the same codebase grows,
session by session, from a local Java program into a fully deployed, observable
system on AWS (EC2 + Docker, DynamoDB, SQS → Lambda → SNS, Terraform, GitHub
Actions CI/CD, CloudWatch + X-Ray).

> The code is teaching material: no web framework, minimal dependencies, and
> heavy comments that explain **why**, not just **what**.

This README grows with the course. Right now it covers **Session 1 — running the
API locally**. (Docker, AWS deploy, and observability sections are added in later
sessions / Git tags — see [SESSIONS.md](SESSIONS.md) once it exists.)

## What it does

A simple CRUD API over a `Task`:

```json
{ "id": "uuid", "title": "Learn Docker", "description": "optional", "done": false, "createdAt": "2026-06-14T12:00:00Z" }
```

| Method   | Path          | Purpose                         | Success |
|----------|---------------|---------------------------------|---------|
| `GET`    | `/health`     | liveness + version              | `200`   |
| `GET`    | `/tasks`      | list all tasks                  | `200`   |
| `POST`   | `/tasks`      | create a task                   | `201`   |
| `GET`    | `/tasks/{id}` | fetch one task                  | `200`   |
| `PUT`    | `/tasks/{id}` | update (full or partial)        | `200`   |
| `DELETE` | `/tasks/{id}` | delete a task                   | `204`   |

Errors use a consistent shape: `{"error":"<CODE>","message":"..."}`.
Every response includes an `X-Request-Id` header, and the server logs one
structured JSON line per request.

## Prerequisites

- **Java 17** (the course LTS). A newer JDK also works — the build targets 17.
- **Maven 3.9+**

## Quickstart (local, no AWS needed)

```bash
# Run the unit tests
make test

# Build and run the API in memory mode on http://localhost:8080
make run
```

Then, in another terminal:

```bash
# Health check
curl -s http://localhost:8080/health
# {"status":"UP","version":"dev"}

# Create a task
curl -s -X POST http://localhost:8080/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Learn Docker"}'
# 201 {"id":"...","title":"Learn Docker","description":null,"done":false,"createdAt":"..."}

# List tasks
curl -s http://localhost:8080/tasks
# {"tasks":[{...}],"count":1}
```

Run `make help` to see all available commands.

## Configuration (environment variables)

The app reads configuration **only** from environment variables. The full table
lives in the PRD (`docs/tasks-api-prd.md`, §10); the ones that matter in Session 1:

| Variable      | Default  | Purpose                                   |
|---------------|----------|-------------------------------------------|
| `APP_PORT`    | `8080`   | Port the HTTP server binds to             |
| `APP_VERSION` | `dev`    | Returned by `/health` (set to git SHA in CI/CD) |
| `STORAGE`     | `memory` | `memory` (default) or `dynamodb` (Session 5) |
| `LOG_LEVEL`   | `INFO`   | `DEBUG` / `INFO` / `WARN` / `ERROR`       |

## Project layout

```
app/                  the Tasks API service (Java)
  src/main/java/com/course/tasksapi/
    App.java          HttpServer bootstrap + routing
    handlers/         HealthHandler, TasksHandler, LoggingHandler, FallbackHandler
    model/Task.java   the one domain object
    repo/             TaskRepository + in-memory implementation + factory
    events/           EventPublisher + no-op implementation + factory
    config/Config.java   reads env vars
    util/             Json, Logging, Http, ApiException
  src/test/java/...   unit + HTTP tests
docs/                 PRD and (later) architecture + runbook
```

## License

See [LICENSE](LICENSE).
