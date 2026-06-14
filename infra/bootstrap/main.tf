# =============================================================================
# State backend bootstrap (PRD §13.1) — run this ONCE, before the main stack.
#
# Chicken-and-egg: the main stack stores its state in S3 with a DynamoDB lock,
# but something has to CREATE that bucket and table first. This tiny module does
# that, using LOCAL state (committed nowhere — see .gitignore).
#
# Usage:
#   cd infra/bootstrap
#   terraform init
#   terraform apply
#   # note the outputs, then configure the main stack's backend with them.
# =============================================================================
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "project_name" {
  type    = string
  default = "tasks-api"
}

data "aws_caller_identity" "current" {}

# Bucket name must be globally unique, so we append the account id.
resource "aws_s3_bucket" "state" {
  bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform-bootstrap"
  }
}

# Keep a history of state files (lets you recover from a bad apply).
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest (it can contain sensitive values).
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# State is private — block all public access.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lock table prevents two `terraform apply` runs from clobbering each other.
resource "aws_dynamodb_table" "lock" {
  name         = "${var.project_name}-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform-bootstrap"
  }
}

output "state_bucket" {
  description = "Pass to the main stack as -backend-config=\"bucket=...\" and var.state_bucket."
  value       = aws_s3_bucket.state.bucket
}

output "lock_table" {
  description = "Pass to the main stack as -backend-config=\"dynamodb_table=...\" and var.lock_table."
  value       = aws_dynamodb_table.lock.name
}
