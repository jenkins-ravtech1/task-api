# =============================================================================
# Elastic Container Registry (PRD §13.3).
#
# A private repository that stores the app's Docker images. CD pushes images here
# (tagged with the git SHA), and the EC2 instance pulls from here.
# =============================================================================

resource "aws_ecr_repository" "app" {
  name                 = local.ecr_repo
  image_tag_mutability = "MUTABLE" # CD re-pushes the `latest` tag each deploy (§14.2)

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

# Keep the repository small (and cheap): expire untagged images quickly and cap
# how many tagged images we retain. Every CD run pushes a new SHA tag, so without
# this the repo would grow forever.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the 10 most recent tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
