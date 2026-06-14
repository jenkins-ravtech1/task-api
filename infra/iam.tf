# =============================================================================
# IAM + GitHub OIDC (PRD §13.4, §17).
#
# The headline idea: GitHub Actions authenticates to AWS with short-lived tokens
# via OIDC (OpenID Connect) — there are NO long-lived AWS access keys anywhere.
# =============================================================================

# ---------------------------------------------------------------------------
# GitHub OIDC provider (an account-wide singleton)
# ---------------------------------------------------------------------------
# Only ONE provider for a given URL can exist per AWS account. If your account
# already has it (common in shared accounts), set create_oidc_provider = false
# and we look it up instead of creating it.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS no longer verifies this thumbprint for the GitHub OIDC endpoint, but the
  # argument is still required; this is the well-known value.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# ---------------------------------------------------------------------------
# Deploy role — assumed by GitHub Actions (the CD pipeline) via OIDC
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "deploy_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    # audience must be the AWS STS audience.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # subject scopes WHICH workflow runs may assume this role. IMPORTANT: when a
    # job declares `environment: production`, GitHub sets the subject to the
    # ENVIRONMENT form, not the branch form — so we must allow it explicitly, or
    # the CD deploy job's AssumeRole call would be denied.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_repo}:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${var.project_name}-deploy"
  description        = "Assumed by GitHub Actions via OIDC to build, push and deploy."
  assume_role_policy = data.aws_iam_policy_document.deploy_assume.json
}

# What the deploy role is allowed to do.
#
# NOTE ON LEAST PRIVILEGE: this role runs `terraform apply` of the WHOLE stack,
# so it inherently needs broad create/manage rights on the services it
# provisions (you cannot scope to ARNs that do not exist yet). We scope tightly
# where we can (state store, ECR repo, image SSM param, PassRole) and grant
# service-level breadth for provisioning, restricting IAM management to this
# project's resource names. For a real production deploy role you would tighten
# this further. See docs/runbook.md.
data "aws_iam_policy_document" "deploy" {
  # --- ECR: log in and push/pull images ---
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:ListImages",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  # --- Terraform remote state: S3 bucket + DynamoDB lock table ---
  statement {
    sid       = "StateBucket"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}", "arn:aws:s3:::${var.state_bucket}/*"]
  }
  statement {
    sid       = "StateLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:${local.region}:${local.account_id}:table/${var.lock_table}"]
  }

  # --- Deploy: update the image-tag SSM parameter and run a command on the box ---
  statement {
    sid       = "ImageTagParam"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter"]
    resources = ["arn:aws:ssm:${local.region}:${local.account_id}:parameter${local.image_tag_param}"]
  }
  # SendCommand is a WRITE action, so scope it tightly to our instance and the
  # shell-script document only.
  statement {
    sid     = "SsmSendCommand"
    actions = ["ssm:SendCommand"]
    resources = [
      aws_instance.app.arn,
      "arn:aws:ssm:${local.region}::document/AWS-RunShellScript",
    ]
  }
  # The result/listing calls are read-only; AWS requires "*" for them.
  statement {
    sid = "SsmReadCommands"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:ListCommands",
    ]
    resources = ["*"]
  }

  # --- Provision the stack (terraform apply needs to read/manage these) ---
  statement {
    sid = "ProvisionServices"
    actions = [
      "ec2:*",
      "ecr:*",
      "dynamodb:*",
      "sqs:*",
      "sns:*",
      "lambda:*",
      "logs:*",
      "cloudwatch:*",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:DescribeParameters",
      "application-autoscaling:*",
      "xray:*",
    ]
    resources = ["*"]
  }

  # --- IAM (read): Terraform must REFRESH every project role/profile (including
  #     the deploy role itself) to detect drift, so reads cover all of them. ---
  statement {
    sid = "IamReadProject"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:GetInstanceProfile",
      "iam:ListInstanceProfilesForRole",
      "iam:GetOpenIDConnectProvider",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${var.project_name}-*",
      "arn:aws:iam::${local.account_id}:instance-profile/${var.project_name}-*",
      "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com",
    ]
  }

  # --- IAM (write): scoped to the INSTANCE and LAMBDA roles ONLY. The deploy
  #     role is deliberately excluded so a compromised CD run cannot widen its
  #     own permissions (privilege-escalation guard). Consequence: changes to the
  #     deploy role itself must be applied locally by an admin (see runbook). ---
  statement {
    sid = "IamWriteWorkloadRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${var.project_name}-instance",
      "arn:aws:iam::${local.account_id}:role/${var.project_name}-lambda",
      "arn:aws:iam::${local.account_id}:instance-profile/${var.project_name}-*",
    ]
  }

  # --- Pass ONLY the workload roles (instance, lambda) — never the deploy role. ---
  statement {
    sid     = "PassWorkloadRoles"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${var.project_name}-instance",
      "arn:aws:iam::${local.account_id}:role/${var.project_name}-lambda",
    ]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.project_name}-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# ---------------------------------------------------------------------------
# EC2 instance role — what the app server itself is allowed to do
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "instance_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.project_name}-instance"
  description        = "Role for the EC2 instance running the Tasks API container."
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
}

# Managed policy that lets Systems Manager manage the instance (this is what
# gives us shell access via Session Manager instead of SSH, and lets CD run
# commands on the box).
resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "instance" {
  # Pull the app image from ECR.
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  # CRUD on the tasks table (the app's storage). Scoped to that table + indexes.
  statement {
    sid = "DynamoCrud"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Scan",
      "dynamodb:Query",
    ]
    resources = [local.table_arn, "${local.table_arn}/index/*"]
  }

  # Publish task-created events to the SQS queue.
  statement {
    sid       = "SqsSend"
    actions   = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
    resources = [local.queue_arn]
  }

  # Read the image-tag SSM parameter (used by the deploy helper on the box).
  statement {
    sid       = "ReadImageTag"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${local.region}:${local.account_id}:parameter${local.image_tag_param}"]
  }

  # Ship logs to CloudWatch and traces to X-Ray (used from session 8).
  statement {
    sid = "Telemetry"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "${var.project_name}-instance"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project_name}-instance"
  role = aws_iam_role.instance.name
}
