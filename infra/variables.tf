# =============================================================================
# Input variables (PRD §13.10).
# Copy terraform.tfvars.example to terraform.tfvars and adjust.
# =============================================================================

variable "project_name" {
  description = "Short name used to prefix resources."
  type        = string
  default     = "tasks-api"
}

variable "environment" {
  description = "Deployment environment name (used in tags)."
  type        = string
  default     = "production"
}

variable "aws_region" {
  description = "AWS region to deploy into. Pick the one closest to students."
  type        = string
  default     = "eu-central-1"
}

variable "github_repo" {
  description = "GitHub repository in 'org/repo' form; scopes the OIDC deploy role."
  type        = string
  default     = "jenkins-ravtech1/task-api"
}

variable "instance_type" {
  description = "EC2 instance type (free-tier friendly)."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port the app listens on (and the security group opens)."
  type        = number
  default     = 8080
}

variable "allowed_cidr" {
  description = "CIDR allowed to reach the app port. WARNING: default is open to the world — restrict to your IP/CIDR for anything real."
  type        = string
  default     = "0.0.0.0/0"
}

variable "notification_email" {
  description = "If non-empty, an email subscription is added to the SNS topic (session 5). You must confirm the subscription via email."
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "Container image tag to run. CD passes the git SHA; defaults to 'latest'."
  type        = string
  default     = "latest"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. An AWS account can have only ONE provider for a given URL, so set this to false if it already exists."
  type        = bool
  default     = true
}

# --- State backend names (created by infra/bootstrap) ------------------------
# Used here only to scope the deploy role's IAM permissions to your state store.
# Set these to match what bootstrap created.

variable "state_bucket" {
  description = "S3 bucket holding Terraform state (from infra/bootstrap output)."
  type        = string
  default     = ""
}

variable "lock_table" {
  description = "DynamoDB table for state locking (from infra/bootstrap output)."
  type        = string
  default     = "tasks-api-tflock"
}
