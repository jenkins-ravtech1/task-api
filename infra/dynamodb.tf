# =============================================================================
# Data store (PRD §13.6).
#
# One DynamoDB table for tasks, with `id` as the partition key. On-demand
# (pay-per-request) billing means no capacity to provision and no idle cost —
# the cost-safe choice for a course.
# =============================================================================

resource "aws_dynamodb_table" "tasks" {
  name         = local.tasks_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # Point-in-time recovery is a paid feature; keep it off for the course.
  point_in_time_recovery {
    enabled = false
  }

  tags = {
    Name = local.tasks_table
  }
}
