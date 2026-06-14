# =============================================================================
# Elastic Container Registry (PRD §13.3).
#
# A private repository that stores the app's Docker images. CD pushes images here
# (tagged with the git SHA), and the EC2 instance pulls from here.
#
# The image lifecycle policy (expire old/untagged images) is added in session 6.
# =============================================================================

resource "aws_ecr_repository" "app" {
  name                 = local.ecr_repo
  image_tag_mutability = "MUTABLE"

  # Scan images for known vulnerabilities as soon as they are pushed.
  image_scanning_configuration {
    scan_on_push = true
  }

  # Let `terraform destroy` delete the repo even if images remain (course safety:
  # everything must be tearable-down).
  force_delete = true

  tags = {
    Name = local.ecr_repo
  }
}
