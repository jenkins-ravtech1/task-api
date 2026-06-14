# Sessions

This repository is built incrementally across an 8-session Cloud/DevOps course.
Each session ends at an annotated Git tag, so you can check out the repo exactly
as it looked at that point:

```bash
git checkout v3-docker     # the repo at the end of session 3
git checkout main          # the final, complete system
```

| Tag | Session | What it adds | Key files |
|-----|---------|--------------|-----------|
| `v1-code` | 1 · Code | Plain-Java HTTP API (in-memory storage), full CRUD, unit + HTTP tests, `make run`, README quickstart. | `app/`, `pom.xml`, `Makefile` |
| `v2-ci` | 2 · Build & Test | GitHub Actions CI: build + test on every push/PR. | `.github/workflows/ci.yml` |
| `v3-docker` | 3 · Package | Multi-stage Dockerfile (non-root, <250 MB), docker-compose with LocalStack, init script creating table/queues/topic. CI also builds the image. | `docker/`, `localstack/init/01-create-resources.sh` |
| `v4-aws-compute` | 4 · Deploy I | Terraform core: backend bootstrap (S3 + lock), default-VPC networking, ECR, IAM + GitHub OIDC, EC2 with user-data. First Lambda stub. | `infra/` (network, ecr, iam, ec2), `infra/bootstrap/`, `lambda/` stub |
| `v5-data-events` | 5 · Deploy II | DynamoDB repository, SQS publisher, Lambda consumer + SNS, messaging/data/lambda Terraform, LocalStack integration tests, full local event chain. | `app/.../repo/DynamoDbTaskRepository.java`, `app/.../events/SqsEventPublisher.java`, `lambda/.../Handler.java`, `infra/{dynamodb,messaging,lambda}.tf` |
| `v6-iac-ecr` | 6 · Deploy III | ECR image lifecycle policy; manual ECR push path; Terraform runs the container on EC2 from ECR. | `infra/ecr.tf`, `Makefile` (`ecr-push`, `tf-*`) |
| `v7-cd` | 7 · Deploy IV | CD pipeline: OIDC → push image → `terraform apply` → SSM deploy → smoke test; `production` approval. | `.github/workflows/cd.yml`, `scripts/smoke-test.sh` |
| `v8-observability` | 8 · Observe | EMF metrics (`TasksCreated`, request latency), CloudWatch logs + alarm, X-Ray tracing via the ADOT agent across API → SQS → Lambda. Docs polish. | `app/.../util/Metrics.java`, `infra/observability.tf`, ADOT wiring in `docker/Dockerfile` + `infra/user-data.sh.tftpl` |
| `main` | — | The final, complete system. | everything |

## Build order (milestones)

The implementation followed the same order: M1 → M8, one reviewable commit and
tag per session. See the [PRD](docs/tasks-api-prd.md) §20 for the milestone
definitions and §21 for the Definition of Done.
