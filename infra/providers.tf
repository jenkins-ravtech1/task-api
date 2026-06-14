# =============================================================================
# Terraform + AWS provider configuration (PRD §5, §13).
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

  # Tag every resource the same way, automatically. Makes cost reports and
  # cleanup trivial ("show me everything tagged Project=tasks-api").
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
