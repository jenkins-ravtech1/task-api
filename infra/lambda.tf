# =============================================================================
# Lambda consumer (PRD §13.8, §9).
#
# The Java Lambda is triggered by messages on the task-events queue (an "event
# source mapping"), and publishes a notification to SNS. X-Ray active tracing is
# on so a trace can span API → SQS → Lambda.
#
# The deployment artifact is lambda/target/lambda.jar — run `mvn -pl lambda -am
# package` (or the full `mvn package`) BEFORE `terraform apply`. CD does this.
# =============================================================================

# --- Lambda execution role (least privilege) ---------------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "SqsConsume"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.events.arn, aws_sqs_queue.dlq.arn]
  }
  statement {
    sid       = "SnsPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.notifications.arn]
  }
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
  statement {
    sid       = "XRay"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.project_name}-lambda"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

# --- The function ------------------------------------------------------------
resource "aws_lambda_function" "events" {
  function_name = local.lambda_function
  role          = aws_iam_role.lambda.arn
  runtime       = "java17"
  handler       = "com.course.tasksevents.Handler"
  memory_size   = 512
  timeout       = 30

  filename         = "${path.module}/../lambda/target/lambda.jar"
  source_code_hash = filebase64sha256("${path.module}/../lambda/target/lambda.jar")

  environment {
    variables = {
      NOTIFICATIONS_TOPIC_ARN = aws_sns_topic.notifications.arn
    }
  }

  # Distributed tracing → X-Ray (used end-to-end in session 8).
  tracing_config {
    mode = "Active"
  }

  # Ensure Terraform owns the log group (with our 14-day retention) before the
  # function exists — otherwise Lambda would auto-create it on first invoke and a
  # later apply could hit ResourceAlreadyExistsException.
  depends_on = [aws_cloudwatch_log_group.lambda]
}

# --- Trigger: SQS → Lambda ---------------------------------------------------
resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = aws_sqs_queue.events.arn
  function_name    = aws_lambda_function.events.arn

  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  # Lets the handler report individual failed messages (partial batch response)
  # instead of failing/retrying the whole batch.
  function_response_types = ["ReportBatchItemFailures"]
}
