# =============================================================================
# Compute (PRD §13.5).
#
# A single free-tier EC2 instance running Amazon Linux 2023. Its user-data
# installs Docker and a small "deploy" helper, then runs the app container as a
# systemd service. The image TAG to run is stored in an SSM parameter, which the
# CD pipeline updates — so deploying a new version is "change the parameter, then
# re-run the helper" (no SSH, no rebuilding the instance).
# =============================================================================

# Resolve the latest Amazon Linux 2023 AMI from the public SSM parameter AWS
# publishes — no hard-coded AMI id that would rot over time.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# The image tag the instance should run. Terraform seeds it; CD overwrites it on
# each deploy, so we ignore_changes to avoid Terraform reverting CD's value.
resource "aws_ssm_parameter" "image_tag" {
  name        = local.image_tag_param
  description = "Container image tag the Tasks API instance should run."
  type        = "String"
  value       = var.image_tag

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  # Require IMDSv2 (token-based metadata) — a basic, free security hardening.
  # hop_limit = 2 so the Docker CONTAINERS on this host can still reach the
  # instance metadata service to get the instance-role credentials (they're one
  # network hop away; the default limit of 1 would block them).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    aws_region      = var.aws_region
    ecr_repo_url    = aws_ecr_repository.app.repository_url
    image_tag_param = local.image_tag_param
    app_port        = var.app_port
    tasks_table     = local.tasks_table
    queue_url       = local.queue_url
    topic_arn       = local.topic_arn
    app_log_group   = local.app_log_group
  })

  # Re-run user-data (i.e. replace the instance) when the script changes.
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-app"
  }
}
