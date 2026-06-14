# =============================================================================
# Locals — the FROZEN naming contract shared across every .tf file.
#
# These names are the single source of truth. IAM policies, the EC2 user-data,
# the SSM parameter, and (in session 5) the actual DynamoDB/SQS/SNS resources all
# refer back here. Building ARNs/URLs from names (instead of resource references)
# lets sessions 4–7 reference resources that a later session creates, with zero
# risk of a name typo drifting between two files.
#
# The names also match localstack/init/01-create-resources.sh, so the local and
# cloud stacks are mirror images.
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  # --- resource names ---
  tasks_table         = "tasks"
  events_queue        = "task-events"
  events_dlq          = "task-events-dlq"
  notifications_topic = "task-notifications"
  ecr_repo            = var.project_name
  image_tag_param     = "/${var.project_name}/image-tag"
  app_log_group       = "/${var.project_name}/app"
  lambda_function     = "${var.project_name}-events"

  # --- ARNs / URLs derived from the names above ---
  table_arn = "arn:aws:dynamodb:${local.region}:${local.account_id}:table/${local.tasks_table}"
  queue_arn = "arn:aws:sqs:${local.region}:${local.account_id}:${local.events_queue}"
  dlq_arn   = "arn:aws:sqs:${local.region}:${local.account_id}:${local.events_dlq}"
  topic_arn = "arn:aws:sns:${local.region}:${local.account_id}:${local.notifications_topic}"
  queue_url = "https://sqs.${local.region}.amazonaws.com/${local.account_id}/${local.events_queue}"
}
