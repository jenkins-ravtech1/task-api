# =============================================================================
# Networking (PRD §13.2).
#
# To stay simple and free, we use the account's DEFAULT VPC and its subnets
# rather than building a custom network. The only resource we create is a
# security group for the app.
# =============================================================================

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app"
  description = "Tasks API: inbound app port from allowed_cidr; egress all. Shell access is via SSM, so no SSH ingress."
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "App HTTP port"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    description = "All outbound (ECR pull, SSM, AWS APIs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app"
  }
}
