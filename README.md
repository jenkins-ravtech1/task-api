# Tasks API

A small, **plain-Java** HTTP API for managing tasks — the reference
implementation for an 8-session Cloud/DevOps course. The same codebase grows,
session by session, from a local Java program into a fully deployed, observable
system on AWS: EC2 + Docker, DynamoDB, SQS → Lambda → SNS, Terraform, GitHub
Actions CI/CD (OIDC), CloudWatch + X-Ray.

> The code is teaching material: no web framework, minimal dependencies, heavily
> commented to explain **why**, not just **what**. See [SESSIONS.md](SESSIONS.md)
> to check out the repo as it looked at the end of any session.

- **Architecture:** [docs/architecture.md](docs/architecture.md)
- **Operations:** [docs/runbook.md](docs/runbook.md)
- **Full spec:** [docs/tasks-api-prd.md](docs/tasks-api-prd.md)

## What it does

CRUD over a `Task`:

```json
{ "id": "uuid", "title": "Learn Docker", "description": "optional", "done": false, "createdAt": "2026-06-14T12:00:00Z" }
```

| Method   | Path          | Purpose                  | Success |
|----------|---------------|--------------------------|---------|
| `GET`    | `/health`     | liveness + version       | `200`   |
| `GET`    | `/tasks`      | list all tasks           | `200`   |
| `POST`   | `/tasks`      | create a task            | `201`   |
| `GET`    | `/tasks/{id}` | fetch one task           | `200`   |
| `PUT`    | `/tasks/{id}` | update (full or partial) | `200`   |
| `DELETE` | `/tasks/{id}` | delete a task            | `204`   |

Errors use a consistent shape `{"error":"<CODE>","message":"..."}`. Every
response carries an `X-Request-Id` header, and the server logs one structured
JSON line per request.

## Prerequisites

- **Java 17** (a newer JDK also works — the build targets 17) and **Maven 3.9+**
- **Docker** (for the container and the local LocalStack stack)
- For cloud deploy: **Terraform ≥ 1.6** and the **AWS CLI**

## Quickstart — run it locally

**Just the app (in-memory, session-1 experience):**

```bash
make test        # run the unit tests
make run         # build + run on http://localhost:8080
```

```bash
curl -s http://localhost:8080/health
# {"status":"UP","version":"dev"}

curl -s -X POST http://localhost:8080/tasks \
  -H 'Content-Type: application/json' -d '{"title":"Learn Docker"}'
# 201 {"id":"...","title":"Learn Docker","done":false,"createdAt":"..."}
```

**The full stack (app + DynamoDB + SQS + Lambda + SNS via LocalStack):**

```bash
make compose-up   # builds the lambda jar, then runs everything
```

Now a `POST /tasks` persists to DynamoDB, enqueues an SQS message, triggers the
Lambda, and publishes to SNS — all locally. `make compose-down` tears it down.
`scripts/local-seed.sh` creates a few sample tasks.

Run `make help` to see every target.

## Configuration (environment variables)

The app reads configuration **only** from environment variables.

| Variable                  | Default       | Purpose                                          |
|---------------------------|---------------|--------------------------------------------------|
| `APP_PORT`                | `8080`        | Port the HTTP server binds to                    |
| `APP_VERSION`             | `dev`         | Returned by `/health`; set to the git SHA in CD  |
| `STORAGE`                 | `memory`      | `memory` or `dynamodb`                            |
| `AWS_REGION`              | —             | AWS region (e.g. `eu-central-1`)                 |
| `AWS_ENDPOINT_URL`        | *(unset)*     | If set, the AWS SDK targets it (LocalStack)      |
| `TASKS_TABLE`             | `tasks`       | DynamoDB table name                              |
| `TASK_EVENTS_QUEUE_URL`   | *(unset)*     | If set, enables the SQS publisher                |
| `NOTIFICATIONS_TOPIC_ARN` | *(unset)*     | SNS topic the Lambda publishes to                |
| `LOG_LEVEL`               | `INFO`        | `DEBUG` / `INFO` / `WARN` / `ERROR`              |
| `OTEL_*`                  | —             | OpenTelemetry/ADOT agent config (tracing)        |

- **Local (compose):** `STORAGE=dynamodb`, `AWS_ENDPOINT_URL=http://localstack:4566`,
  and the queue/topic wired to the LocalStack resources (see `docker/docker-compose.yml`).
- **Cloud:** Terraform sets these on the EC2 instance (see `infra/user-data.sh.tftpl`).

## Deploy to AWS

Full details in [docs/runbook.md](docs/runbook.md). In short:

1. **Bootstrap state** (once): `cd infra/bootstrap && terraform init && terraform apply`.
2. **Configure** `infra/terraform.tfvars` (set `github_repo`, restrict
   `allowed_cidr`, set `state_bucket`).
3. **First apply** (run locally as an admin — the deploy role doesn't exist yet):
   `terraform init -backend-config=...` then `terraform apply`.
4. **Create the GitHub OIDC deploy role** (done by that apply) and set the repo
   **variables**: `AWS_REGION`, `AWS_DEPLOY_ROLE_ARN`, `ECR_REPOSITORY`,
   `TF_STATE_BUCKET`, `TF_LOCK_TABLE`.
5. **Push to `main`** → approve the `production` environment → CD builds, pushes
   to ECR, applies Terraform, deploys via SSM, and smoke-tests.

There are **no long-lived AWS keys** anywhere — GitHub authenticates via OIDC.

## Observability

- **Logs:** structured JSON to stdout → CloudWatch Logs (queryable with Logs
  Insights).
- **Metrics:** EMF lines double as CloudWatch metrics — `TasksCreated` (count)
  and request latency (ms) in the `TasksApi` namespace.
- **Alarm:** any app `5xx` or Lambda error in 5 minutes notifies SNS.
- **Traces:** the ADOT/OpenTelemetry Java agent (no app code changes) exports to
  X-Ray; one trace spans API → SQS → Lambda.

## Cost & cleanup

Sized for the **AWS Free Plan** ($200 credit / 6 months): `t3.micro`, on-demand
DynamoDB, short log retention, no NAT/load balancer. Set an AWS **Budget** alert.

Tear everything down when you're done:

```bash
make destroy                       # destroys the main stack
cd infra/bootstrap && terraform destroy   # (optional) the state backend too
```

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `make compose-up` Lambda step is skipped | Build the jar: `mvn -pl lambda -am package`. |
| Integration tests skipped locally | Testcontainers can't reach Docker; they run in CI. Enable Docker's default socket. |
| App can't reach DynamoDB on EC2 | Containers need IMDS hop limit 2 (set in `ec2.tf`). |
| `/health` down right after first apply | ECR is empty until the first image push — expected (see runbook). |
| CD fails at AWS auth | OIDC `sub` mismatch — the deploy role trusts the `production` environment subject. |

## Project layout

```
app/                  Tasks API service (Java)
lambda/               SQS consumer Lambda (Java)
docker/               Dockerfile, .dockerignore lives at repo root, docker-compose
localstack/init/      scripts that set up LocalStack on startup
infra/                Terraform (root module) + bootstrap/ (state backend)
scripts/              local-seed.sh, smoke-test.sh
.github/workflows/    ci.yml, cd.yml
docs/                 architecture.md, runbook.md, PRD
```

## License

[MIT](LICENSE).
