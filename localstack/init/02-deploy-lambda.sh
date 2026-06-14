#!/usr/bin/env bash
# =============================================================================
# Deploys the consumer Lambda to LocalStack and wires it to the SQS queue, so the
# FULL local chain works: POST /tasks → SQS → Lambda → SNS (PRD §11, FR-LD-2).
#
# Requires the built jar mounted at /opt/lambda/lambda.jar — build it first with
#   mvn -pl lambda -am package
# (the `make compose-up` target does this for you). If the jar is missing this
# script skips, and the DynamoDB + SQS parts of the demo still work.
# =============================================================================
set -euo pipefail

REGION="eu-central-1"
JAR="/opt/lambda/lambda.jar"
FUNCTION="task-events"
QUEUE_ARN="arn:aws:sqs:${REGION}:000000000000:task-events"
TOPIC_ARN="arn:aws:sns:${REGION}:000000000000:task-notifications"

if [ ! -f "${JAR}" ]; then
  echo "[init] lambda jar not found at ${JAR} — skipping Lambda deploy."
  echo "[init] build it with:  mvn -pl lambda -am package"
  exit 0
fi

echo "[init] creating Lambda function: ${FUNCTION}"
awslocal lambda create-function \
  --function-name "${FUNCTION}" \
  --runtime java17 \
  --handler com.course.tasksevents.Handler \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --zip-file "fileb://${JAR}" \
  --timeout 30 \
  --memory-size 512 \
  --environment "Variables={NOTIFICATIONS_TOPIC_ARN=${TOPIC_ARN},AWS_ENDPOINT_URL=http://localstack:4566}" \
  --region "${REGION}" \
  >/dev/null

echo "[init] waiting for the function to become Active"
awslocal lambda wait function-active-v2 --function-name "${FUNCTION}" --region "${REGION}" || true

echo "[init] wiring SQS -> Lambda (event source mapping)"
awslocal lambda create-event-source-mapping \
  --function-name "${FUNCTION}" \
  --event-source-arn "${QUEUE_ARN}" \
  --batch-size 10 \
  --function-response-types ReportBatchItemFailures \
  --region "${REGION}" \
  >/dev/null

echo "[init] lambda deploy done — the full event chain is live."
