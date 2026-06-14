# Demo — run the full stack locally and show every capability

A step-by-step script for demonstrating the Tasks API end to end on a laptop,
using LocalStack (a single container that emulates AWS). No AWS account, no cost.
(Cloud deploy is in the [runbook](runbook.md); the design is in
[architecture.md](architecture.md).)

> Everything below was run against the local stack and works as written. Each
> `POST /tasks` travels the whole path: **API → DynamoDB → SQS → Lambda → SNS**.

## 0. Bring the stack up

```bash
make compose-up      # builds the lambda jar, then runs app + LocalStack
```

The first run is slow (the image targets `linux/amd64` and builds under emulation
on Apple Silicon); reruns are cached and fast. Wait until the logs show
`[init] lambda deploy done — the full event chain is live`, then:

```bash
curl -s http://localhost:8080/health
# {"status":"UP","version":"local"}
```

Tear it all down at the end with `make compose-down` (the `-v` flag in that
target also removes the volumes, so you start clean next time).

## Reading the curl commands

Every request below is plain `curl`. These are the only flags used:

| Flag          | Long form   | What it does                           | Why it's here                                                 |
|---------------|-------------|----------------------------------------|---------------------------------------------------------------|
| `-s`          | `--silent`  | Print only the response body           | Clean output; pipes straight into `jq`                        |
| `-i`          | `--include` | Include the response **headers**       | When the header is the point: `201`, `Location`, `Allow`      |
| `-X <method>` | `--request` | Set the HTTP method                    | Needed for `PUT`/`DELETE`; explicit on `POST` for clarity     |
| `-H <header>` | `--header`  | Add a request header                   | `Content-Type: application/json` — else the API returns `415` |
| `-d <data>`   | `--data`    | Send a request body (the JSON payload) | Carries the task fields on create/update                      |

Two `curl` defaults worth knowing — they explain why the flags pair up the way
they do:

- Passing `-d` makes curl **default to `POST`**, so `-X POST` on a create is
  technically redundant. It's kept for clarity; `PUT`/`DELETE` genuinely need
  `-X`.
- Passing `-d` also defaults the Content-Type to
  `application/x-www-form-urlencoded`. That's exactly why every write request
  **must** add `-H 'Content-Type: application/json'` — to override that default,
  or the API returns `415`.

Not curl, but they appear alongside it:

| Token        | What it is | What it does                                                                |
|--------------|------------|-----------------------------------------------------------------------------|
| `\| jq`      | shell pipe | Pretty-prints/colours the JSON response (install `jq`, or drop it)          |
| `>/dev/null` | shell      | Discards the body when only the side effect matters (e.g. firing the event) |

## 1. The API — full CRUD

```bash
# Create — note the 201 status and the Location header pointing at the new task
curl -i -X POST http://localhost:8080/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Learn Docker","description":"for the demo"}'

# Seed a few sample tasks at once
scripts/local-seed.sh

# List
curl -s http://localhost:8080/tasks | jq

# Grab an id from the list above, then read / update / delete it:
curl -s http://localhost:8080/tasks/<id> | jq                       # 200 read one
curl -s -X PUT http://localhost:8080/tasks/<id> \
  -H 'Content-Type: application/json' -d '{"done":true}' | jq       # 200 partial update
curl -i -X DELETE http://localhost:8080/tasks/<id>                  # 204 no content
```

`PUT` is a **partial** update: send only the fields you want to change
(`{"done":true}` flips just that flag). The server always controls `id`,
`createdAt` and the initial `done` — client values for those are ignored.

## 2. Prove it's really persisting to (fake) AWS

This is the "it's actually cloud, not an in-memory map" moment — read straight
from DynamoDB inside the LocalStack container:

```bash
docker exec tasks-api-localstack-1 \
  awslocal dynamodb scan --table-name tasks --region eu-central-1 \
  --query "Items[].{id:id.S,title:title.S,done:done.BOOL}" --output table
```

`awslocal` is just the AWS CLI pre-pointed at LocalStack, so this is the same
command you'd run against real AWS — only the endpoint differs.

## 3. The event-driven pipeline (the headline feature)

Creating a task publishes a `TASK_CREATED` message to SQS; that triggers the
Lambda; the Lambda publishes a notification to SNS. To *see* the notification,
subscribe a throwaway queue to the SNS topic first.

```bash
# One-time setup: an "inbox" queue subscribed to the notifications topic
docker exec tasks-api-localstack-1 bash -lc '
R=eu-central-1
T=$(awslocal sns create-topic --name task-notifications --region $R --query TopicArn --output text)
Q=$(awslocal sqs create-queue --queue-name demo-inbox --region $R --query QueueUrl --output text)
A=$(awslocal sqs get-queue-attributes --queue-url "$Q" --attribute-names QueueArn --region $R --query Attributes.QueueArn --output text)
awslocal sns subscribe --topic-arn "$T" --protocol sqs --notification-endpoint "$A" --attributes RawMessageDelivery=true --region $R'
```

```bash
# Create a task...
curl -s -X POST http://localhost:8080/tasks \
  -H 'Content-Type: application/json' -d '{"title":"Notify me!"}' >/dev/null

# ...then read the notification the Lambda produced (allow a few seconds):
docker exec tasks-api-localstack-1 \
  awslocal sqs receive-message \
  --queue-url http://localhost:4566/000000000000/demo-inbox \
  --region eu-central-1 --query "Messages[].Body" --output text
# -> A new task was created: "Notify me!" (id ...)
```

**Talking point:** the API returns `201` *immediately* — it does not wait for the
notification. SQS decouples the two, so a slow or failing notifier never slows
down (or breaks) task creation. Publishing the event is best-effort: if SQS were
down, the task is still created and a warning is logged.

> The `demo-inbox` queue and subscription are created at runtime only (not in the
> code or Terraform), so they vanish on `make compose-down`. Re-run the one-time
> setup each session.

### Show the safety net (optional)

The queue has a dead-letter queue (DLQ): after 3 failed processing attempts a
message is parked there instead of looping forever. In a healthy run both are
empty — an empty main queue *and* an empty DLQ together prove the Lambda consumed
the message cleanly:

```bash
docker exec tasks-api-localstack-1 bash -lc '
for q in task-events task-events-dlq; do
  URL=$(awslocal sqs get-queue-url --queue-name $q --region eu-central-1 --query QueueUrl --output text)
  echo -n "$q -> "; awslocal sqs get-queue-attributes --queue-url "$URL" \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
    --region eu-central-1 --query Attributes --output json
done'
```

## 4. Error handling

The API returns a consistent error shape `{"error":"<CODE>","message":"..."}`
with the right HTTP status:

```bash
curl -s -X POST http://localhost:8080/tasks -H 'Content-Type: application/json' -d '{}'      # 400 VALIDATION (title required)
curl -s -X POST http://localhost:8080/tasks -H 'Content-Type: text/plain'   -d 'hi'          # 415 must be application/json
curl -i -X POST http://localhost:8080/tasks/anything                                          # 405 + Allow header
curl -i http://localhost:8080/nope                                                            # 404 unknown route
```

## 5. Observability

```bash
# Structured JSON logs — one line per request, each with its own requestId
docker logs tasks-api-app-1 | grep '"path":"/tasks"' | tail -5

# EMF metric lines — in real AWS, CloudWatch reads these as the TasksCreated
# count and durationMs latency in the "TasksApi" namespace
docker logs tasks-api-app-1 | grep TasksCreated | tail -3
```

A single EMF (Embedded Metric Format) line is *both* a log entry and a metric, so
the app emits CloudWatch metrics without any extra metrics API calls.

## What this local demo does NOT cover

LocalStack here runs only `dynamodb, sqs, sns, s3, lambda`. **CloudWatch Logs,
the CloudWatch alarm, and X-Ray tracing need real AWS**, so they only light up in
an actual deploy (`make tf-apply`, or the CD pipeline). In the cloud, one X-Ray
trace spans API → SQS → Lambda, and any `5xx`/Lambda error in a 5-minute window
fires an alarm to SNS. See the [runbook](runbook.md) for that path.

## Teardown

```bash
make compose-down    # stops containers and removes volumes
```

---

## Part 2 — the same demo against the live AWS stack

Everything above ran against LocalStack (fake AWS, free). This part runs the
**identical API** against the **real** deployment in AWS, side by side. The point
of the demo is that the application code and the commands barely change — only the
base URL and the fact that AWS is now real (and billable).

> Prerequisite: the stack is deployed (CD has run at least once). If it isn't,
> see [Bring it back up](#bring-it-back-up) below. AWS credentials must be
> configured locally (`aws sts get-caller-identity` should succeed).

### Side-by-side: LocalStack vs live AWS

Get the live URL from Terraform (never hard-code it — the public DNS changes every
time the instance is recreated):

```bash
LIVE=$(terraform -chdir=infra output -raw api_base_url)
echo "$LIVE"   # e.g. http://ec2-XX-XX-XX-XX.eu-central-1.compute.amazonaws.com:8080
```

> Note: the live security group currently allows port 8080 from `0.0.0.0/0` (open
> to the internet) so the demo URL works from anywhere. It's a throwaway course
> deployment; for anything real, restrict `allowed_cidr`.

**Health — local vs cloud.** The version field is the tell: local reports
`local`; the cloud reports the **git SHA that CD deployed**, so you can see exactly
which commit is live.

```bash
curl -s http://localhost:8080/health   # {"status":"UP","version":"local"}
curl -s "$LIVE/health"                 # {"status":"UP","version":"<git-sha>"}
```

**Same CRUD, different URL.** Every command from [section 1](#1-the-api--full-crud)
works verbatim against `$LIVE`:

```bash
curl -i -X POST "$LIVE/tasks" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Learn Docker","description":"in real AWS"}'   # 201 + Location

curl -s "$LIVE/tasks" | jq                                    # list
```

**Prove it persists to REAL DynamoDB.** Locally you ran `awslocal` inside the
container; in the cloud it's the same command with the plain `aws` CLI against the
real table — that mirror is the whole reason LocalStack is a faithful stand-in:

```bash
aws dynamodb scan --table-name tasks --region eu-central-1 \
  --query "Items[].{id:id.S,title:title.S,done:done.BOOL}" --output table
```

**The event pipeline — read it from CloudWatch (the cloud's advantage).** Locally
you subscribed a throwaway `demo-inbox` queue to see the notification. In the cloud
the managed services hand you logs, metrics and traces for free, so the cleanest
proof is to watch the Lambda process the event:

```bash
# Create a task on the live app...
curl -s -X POST "$LIVE/tasks" -H 'Content-Type: application/json' \
  -d '{"title":"Notify me (cloud)!"}' >/dev/null

# ...then watch the Lambda consume it (Ctrl-C to stop; allow a few seconds):
aws logs tail /aws/lambda/tasks-api-events --since 2m --follow --region eu-central-1
# -> {"event":"TASK_CREATED","taskId":"...","title":"Notify me (cloud)!"}
#    each line also carries an "XRAY TraceId:" — the trace is real in the cloud.
```

Check the queue drained cleanly (same idea as the local DLQ check, real CLI):

```bash
QURL=$(terraform -chdir=infra output -raw queue_url)
aws sqs get-queue-attributes --queue-url "$QURL" \
  --attribute-names ApproximateNumberOfMessages --region eu-central-1 \
  --query Attributes --output json     # ApproximateNumberOfMessages: "0"
```

**Observability that only lights up in real AWS** (the local demo's section 5 had
to use `docker logs`; here it's CloudWatch):

```bash
# Structured JSON request logs — one line per request, each with its requestId
aws logs tail /tasks-api/app --since 10m --region eu-central-1 | grep '"path":"/tasks"' | tail -5

# EMF metric lines — CloudWatch reads these as TasksCreated / durationMs in the
# "TasksApi" namespace (one line is BOTH a log entry and a metric)
aws logs tail /tasks-api/app --since 10m --region eu-central-1 | grep TasksCreated | tail -3
```

Plus the **CloudWatch alarm** (any `5xx` or Lambda error in a 5-minute window fires
to SNS) and the **X-Ray** service map for the Lambda — neither exists under
LocalStack. See [architecture.md](architecture.md) and the [runbook](runbook.md).

> ⚠️ Known issue: the EC2 app's OpenTelemetry agent is still pointed at
> `http://otel-collector:4317` (a docker-compose-only hostname), so on EC2 its span
> export fails — you'll see `Failed to export spans … Connection reset` noise in
> `/tasks-api/app`. It's harmless (health, CRUD, events, EMF metrics, and the
> Lambda's own X-Ray traces all work), but the **app's** traces don't reach X-Ray
> until the OTLP endpoint is fixed (or the OTLP exporter is disabled for the cloud).

#### At a glance

| Aspect | LocalStack (Part 1) | Live AWS (Part 2) |
| --- | --- | --- |
| Base URL | `http://localhost:8080` | `terraform output -raw api_base_url` |
| AWS | emulated, free | real, billable (~a few $/mo, mostly the EC2) |
| Inspect AWS with | `awslocal` (inside the container) | `aws` |
| `/health` version | `local` | the deployed git SHA |
| Logs / metrics / alarm / X-Ray | not available | live in CloudWatch / X-Ray |
| Tear down | `make compose-down` | `make destroy` |

### Destroy everything on AWS

Cost safety — remove all the running infrastructure when you're done:

```bash
make destroy        # terraform destroy: removes all 25 main-stack resources
```

- The ECR repo has `force_delete = true`, so it's removed even though it holds
  images — `make destroy` needs no manual cleanup first.
- This does **not** remove the **state backend** (the S3 bucket + DynamoDB lock
  table created once by `infra/bootstrap`). That's a separate module and costs
  almost nothing, so keep it — you'll reuse it next time you bring the stack up.
- After destroy, steady-state cost is ≈ $0 (the standing charge was the `t3.micro`).

Confirm nothing is left running:

```bash
aws ec2 describe-instances --region eu-central-1 \
  --filters Name=tag:Project,Values=tasks-api Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text   # (empty)
```

> Removing the backend too is rarely worth it. If you must: the state bucket has
> versioning on and still holds the (now-empty) state file, so empty all object
> versions first, then `cd infra/bootstrap && terraform destroy`.

### Bring it back up

The GitHub repo variables and the OIDC trust are recreated with the same names, so
**CD is ready again the moment the stack exists** — no GitHub re-config needed.

```bash
# 0. Fresh clone only: terraform.tfvars is gitignored, so recreate it.
cp infra/terraform.tfvars.example infra/terraform.tfvars   # then edit the values

# 1. Fresh clone / destroyed backend only: init against the S3 backend.
#    (A machine that applied before already has .terraform configured — skip this.)
#    The exact -backend-config flags are in docs/runbook.md.

# 2. Recreate all infrastructure (the new EC2 boots with an EMPTY ECR):
make tf-apply

# 3. The instance waits for an image. Let CD build & deploy it (unattended):
gh workflow run cd.yml --ref main        # or just push a commit to main
#    ...or do it manually instead:
#    make ecr-push      # then the put-parameter + send-command steps in the runbook

# 4. Grab the NEW url (public DNS changes each recreate) and smoke test:
LIVE=$(terraform -chdir=infra output -raw api_base_url)
scripts/smoke-test.sh "$LIVE"
```

Same first-apply ordering caveats as the very first bring-up apply (the deploy role
doesn't exist until the first apply; ECR is empty until the first image; a change to
the deploy role's *own* permissions must be applied locally by an admin, not by CD).
Those are all explained in the [runbook](runbook.md).
