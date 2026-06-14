# =============================================================================
# Outputs (PRD §13.10). Printed after `terraform apply`; consumed by CD and by
# students running smoke tests. (queue_url / topic_arn are added in session 5.)
# =============================================================================

output "ecr_repository_url" {
  description = "Push images here; the instance pulls from here."
  value       = aws_ecr_repository.app.repository_url
}

output "deploy_role_arn" {
  description = "Set this as the AWS_DEPLOY_ROLE_ARN repository variable for CD."
  value       = aws_iam_role.deploy.arn
}

output "instance_id" {
  description = "EC2 instance id (CD targets it with SSM RunCommand)."
  value       = aws_instance.app.id
}

output "api_base_url" {
  description = "Base URL of the running API."
  value       = "http://${aws_instance.app.public_dns}:${var.app_port}"
}

output "tasks_table_name" {
  description = "DynamoDB table name."
  value       = local.tasks_table
}

output "image_tag_parameter" {
  description = "SSM parameter that holds the image tag to run."
  value       = local.image_tag_param
}
