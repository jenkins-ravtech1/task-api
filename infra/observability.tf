# =============================================================================
# Observability (PRD §13.9, §15).
#
#   Logs    → CloudWatch log groups (app + Lambda), 14-day retention.
#   Metrics → the app emits EMF lines that CloudWatch turns into metrics
#             (TasksCreated, durationMs) in the "TasksApi" namespace; plus a
#             metric filter that counts 5xx responses.
#   Alarm   → any app 5xx OR any Lambda error in 5 minutes notifies the SNS topic.
#   Traces  → X-Ray (app via the ADOT collector on EC2; Lambda via active tracing).
# =============================================================================

# --- Log groups --------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = local.app_log_group
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_function}"
  retention_in_days = 14
}

# --- 5xx metric from the app logs --------------------------------------------
# The app's per-request EMF line has a numeric `status` field. This filter counts
# every line where status >= 500 into a custom Api5xxCount metric.
resource "aws_cloudwatch_log_metric_filter" "api_5xx" {
  name           = "${var.project_name}-5xx"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.status >= 500 }"

  metric_transformation {
    name          = "Api5xxCount"
    namespace     = "TasksApi"
    value         = "1"
    default_value = "0"
  }
}

# --- Alarms (action → SNS) ---------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.project_name}-5xx"
  alarm_description   = "App returned one or more 5xx responses within 5 minutes."
  namespace           = "TasksApi"
  metric_name         = "Api5xxCount"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.notifications.arn]
  ok_actions          = [aws_sns_topic.notifications.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  alarm_description   = "The events Lambda reported one or more errors within 5 minutes."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.events.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.notifications.arn]
}
