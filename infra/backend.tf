# =============================================================================
# Remote state backend (PRD §13.1).
#
# Terraform state is stored in S3 (so the team/CI share one source of truth) and
# locked with a DynamoDB table (so two applies can't run at once). The bucket and
# lock table are created ONCE by infra/bootstrap/ — which necessarily uses local
# state, because it is what creates this backend.
#
# A backend block cannot use variables, so we leave it PARTIAL and pass the real
# values at init time (see docs/runbook.md):
#
#   terraform init \
#     -backend-config="bucket=tasks-api-tfstate-<account-id>" \
#     -backend-config="key=tasks-api/terraform.tfstate" \
#     -backend-config="region=eu-central-1" \
#     -backend-config="dynamodb_table=tasks-api-tflock"
#
# For local experimentation you can skip the backend entirely:
#   terraform init -backend=false
# =============================================================================
terraform {
  backend "s3" {
    encrypt = true
  }
}
