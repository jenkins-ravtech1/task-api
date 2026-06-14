# Runbook — deploy, redeploy, roll back, troubleshoot

Operational guide for the Tasks API on AWS. (Local development is in the
[README](../README.md); the architecture is in [architecture.md](architecture.md).)

> Everything is created by Terraform. Nothing is clicked in the console.

## One-time: bootstrap the state backend

Terraform stores its state in S3 with a DynamoDB lock. Something has to create
those first, so a tiny separate module (`infra/bootstrap`) does it using local
state:

```bash
cd infra/bootstrap
terraform init
terraform apply
# Note the outputs: state_bucket and lock_table.
```

## One-time: configure and apply the main stack

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set github_repo, allowed_cidr (restrict it!),
# state_bucket (from bootstrap), and create_oidc_provider.

# Initialize with the S3 backend (values from bootstrap):
terraform init \
  -backend-config="bucket=<state_bucket>" \
  -backend-config="key=tasks-api/terraform.tfstate" \
  -backend-config="region=eu-central-1" \
  -backend-config="dynamodb_table=<lock_table>"

terraform apply
```

### ⚠️ First-apply ordering (read this)

There is a deliberate chicken-and-egg the first time:

1. **The deploy role does not exist until the first apply creates it.** So the
   CI/CD pipeline cannot perform the *very first* apply — run it **locally as an
   admin**. After that, CD assumes the deploy role for all subsequent applies.
2. **ECR is empty on the first apply.** The EC2 instance boots and its
   `deploy-app.sh` helper **waits** (retry loop) for an image to appear. The app
   only becomes healthy after the first image is pushed — which the CD pipeline
   does (session 7), or you can do manually (below). This is expected; the
   instance is not "broken" while it waits.
3. **The deploy role cannot modify itself (privilege-escalation guard).** Its
   IAM write permissions are scoped to the instance/lambda roles only, never
   `*-deploy`. So any change to the deploy role's own permissions must be applied
   **locally by an admin**, not by CD. (CD can still read the deploy role for
   drift detection.)

### OIDC subject note

The deploy role's trust policy allows two GitHub subjects:
`repo:<org>/<repo>:ref:refs/heads/main` **and**
`repo:<org>/<repo>:environment:production`. The second is the one that actually
matters: because the CD deploy job uses `environment: production`, GitHub issues
the token with the *environment* subject, not the branch subject. If you ever see
`Not authorized to perform sts:AssumeRoleWithWebIdentity`, check that the job's
`environment:` and the trust policy's `sub` agree.

## Deploy a new version (what CD automates)

Deploying = change the image tag the instance runs, then re-run the helper:

```bash
# 1. Build & push the image to ECR (tagged with the git SHA).
# 2. Point the SSM parameter at the new tag:
aws ssm put-parameter --name "/tasks-api/image-tag" --type String \
  --value "<git-sha>" --overwrite --region eu-central-1
# 3. Tell the instance to pull & restart (no SSH — via SSM RunCommand):
aws ssm send-command --instance-ids <instance_id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["/usr/local/bin/deploy-app.sh"]' \
  --region eu-central-1
# 4. Smoke test:
scripts/smoke-test.sh "$(terraform -chdir=infra output -raw api_base_url)"
```

## Roll back

Point the image tag back at the previous good SHA and redeploy (same three
commands above with the old tag). Because each deploy is just "which tag to run",
rollback is instant and needs no rebuild. Infra changes roll back via
`terraform apply` of the previous configuration.

## Tear everything down (cost safety)

```bash
cd infra && terraform destroy
# Optionally also remove the state backend:
cd bootstrap && terraform destroy
```

## Common incidents

| Symptom | Likely cause | Action |
|---|---|---|
| App `/health` never comes up after first apply | ECR still empty | Push an image (run CD or the manual deploy steps). |
| CD fails at "configure-aws-credentials" | OIDC `sub` mismatch | Check the job's `environment:` vs the trust policy `sub`. |
| `terraform plan` not clean after apply | drift or `ignore_changes` gap | Re-run `apply`; inspect the diff. The image-tag param is intentionally `ignore_changes`. |
| Deploy succeeded but old version served | SSM param not updated, or helper not re-run | Re-run the put-parameter + send-command steps. |

## Optional local tooling

`terraform validate` checks syntax and references but not AWS-specific
correctness. For deeper local checks, install [`tflint`](https://github.com/terraform-linters/tflint)
(`brew install tflint`) and run it in `infra/`.
