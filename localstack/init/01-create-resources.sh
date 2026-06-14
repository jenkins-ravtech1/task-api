#!/usr/bin/env bash
# =============================================================================
# LocalStack init script (PRD §11, FR-LD-2).
#
# This runs INSIDE the LocalStack container once it is ready (it is mounted into
# /etc/localstack/init/ready.d by docker-compose). It creates the same resources
# that Terraform creates in AWS, so the local stack mirrors the cloud:
#   * a DynamoDB table for tasks
#   * an SQS queue + dead-letter queue (DLQ) for task events
#   * an SNS topic for notifications
#
# `awslocal` is the AWS CLI pre-wired to talk to LocalStack (endpoint + creds),
# so we don't have to pass --endpoint-url everywhere.
#
# The Lambda function and its SQS trigger are deployed in session 5, once the
# lambda module produces a build artifact.
# =============================================================================
set -euo pipefail

# NOTE: pin the region explicitly. LocalStack runs these ready.d hooks with
# AWS_REGION=us-east-1 in the environment, so reading $AWS_REGION here would
# create the resources in the wrong region (the app uses eu-central-1). Keeping
# this in lock-step with the app's AWS_REGION is what makes the local stack work.
REGION="eu-central-1"
TABLE="${TASKS_TABLE:-tasks}"
QUEUE="task-events"
DLQ="task-events-dlq"
TOPIC="task-notifications"

echo "[init] creating DynamoDB table: ${TABLE}"
awslocal dynamodb create-table \
  --table-name "${TABLE}" \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${REGION}" \
  >/dev/null

echo "[init] creating SQS dead-letter queue: ${DLQ}"
DLQ_URL=$(awslocal sqs create-queue \
  --queue-name "${DLQ}" \
  --region "${REGION}" \
  --query QueueUrl --output text)

DLQ_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url "${DLQ_URL}" \
  --attribute-names QueueArn \
  --region "${REGION}" \
  --query 'Attributes.QueueArn' --output text)

echo "[init] creating SQS main queue with redrive to DLQ: ${QUEUE}"
# After 3 failed receives, a message is moved to the DLQ instead of looping.
awslocal sqs create-queue \
  --queue-name "${QUEUE}" \
  --region "${REGION}" \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"${DLQ_ARN}\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}" \
  >/dev/null

echo "[init] creating SNS topic: ${TOPIC}"
awslocal sns create-topic --name "${TOPIC}" --region "${REGION}" >/dev/null

echo "[init] done — DynamoDB, SQS (+DLQ) and SNS are ready."
