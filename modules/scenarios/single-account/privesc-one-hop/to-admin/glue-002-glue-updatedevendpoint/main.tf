# Glue UpdateDevEndpoint privilege escalation scenario
#
# This scenario demonstrates how a user with glue:UpdateDevEndpoint can add their
# SSH public key to an existing Glue dev endpoint, SSH into it, and execute commands
# with the endpoint's privileged role to gain admin access.

# Resource naming convention: pl-prod-glue-002-to-admin-{resource-type}
# All resources use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-glue-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-glue-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "glue-updatedevendpoint"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting UpdateDevEndpoint and endpoint discovery permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-glue-002-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:UpdateDevEndpoint"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDevEndpoint",
          "glue:GetDevEndpoints"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target admin role (attached to the dev endpoint)
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-glue-002-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-glue-002-to-admin-target-role"
    Environment = var.environment
    Scenario    = "glue-updatedevendpoint"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Attach AWS managed Glue service policy
resource "aws_iam_role_policy_attachment" "target_role_glue_service" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Pre-existing Glue dev endpoint (already created and running)
# CRITICAL: NO PUBLIC KEYS initially - attacker will add via UpdateDevEndpoint
resource "aws_glue_dev_endpoint" "target_endpoint" {
  provider = aws.prod
  name     = "pl-prod-glue-002-to-admin-endpoint"
  role_arn = aws_iam_role.target_role.arn

  # Use Glue version 1.0 (supports dev endpoints)
  glue_version = "1.0"

  # Minimum number of nodes
  number_of_nodes = 2

  # NO public_keys specified - attacker will add their SSH key via UpdateDevEndpoint

  tags = {
    Name        = "pl-prod-glue-002-to-admin-endpoint"
    Environment = var.environment
    Scenario    = "glue-updatedevendpoint"
    Purpose     = "target-endpoint"
  }
}
