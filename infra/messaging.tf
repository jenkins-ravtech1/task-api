# =============================================================================
# Messaging (PRD §13.7, §9).
#
#   POST /tasks → SQS (task-events) → Lambda → SNS (task-notifications)
#
# The main queue has a dead-letter queue (DLQ): a message that fails to process
# 3 times is moved to the DLQ instead of being retried forever.
# =============================================================================

resource "aws_sqs_queue" "dlq" {
  name = local.events_dlq

  tags = {
    Name = local.events_dlq
  }
}

resource "aws_sqs_queue" "events" {
  name = local.events_queue

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = local.events_queue
  }
}

resource "aws_sns_topic" "notifications" {
  name = local.notifications_topic

  tags = {
    Name = local.notifications_topic
  }
}

# Optional email subscription. If notification_email is set, AWS sends a
# confirmation email the student must click before notifications arrive.
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
