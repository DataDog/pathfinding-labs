terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# Glue CreateDevEndpoint privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and glue:CreateDevEndpoint
# can create a Glue development endpoint with an administrative role and execute commands
# via SSH to achieve privilege escalation.

# Resource naming convention: pl-prod-glue-001-to-admin-{resource-type}
# For single account scenarios, use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-glue-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-glue-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createdevendpoint"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with PassRole and Glue permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-glue-001-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "RequiredForExploitationGlue"
        Effect = "Allow"
        Action = [
          "glue:CreateDevEndpoint"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "glue:GetDevEndpoint",
          "iam:ListRoles",
          "glue:DeleteDevEndpoint"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target admin role that will be passed to Glue
resource "aws_iam_role" "target_role" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-glue-001-to-admin-target-role"

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
    Name        = "pl-prod-glue-001-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createdevendpoint"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/glue-001-to-admin"
  description = "CTF flag for the glue-001 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-glue-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createdevendpoint"
    Purpose     = "ctf-flag"
  }
}
