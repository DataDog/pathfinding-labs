# PassRole + GameLift CreateBuild + CreateFleet privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, gamelift:CreateBuild,
# and gamelift:CreateFleet can escalate to admin by uploading a malicious game
# server build and creating a fleet with an admin instance role. The game server
# process reads the instance role credentials from the shared credentials file
# and uses them to attach AdministratorAccess to the starting user.

# Resource naming convention: pl-prod-gamelift-001-to-admin-{resource-type}
# gamelift-001 = pathfinding.cloud ID for PassRole + GameLift CreateBuild + GameLift CreateFleet

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam-passrole+gamelift-createbuild+gamelift-createfleet privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, gamelift:CreateBuild, and
# gamelift:CreateFleet can escalate privileges by uploading a malicious game server build
# and creating a fleet with an admin instance role. The game server process reads instance
# role credentials from the shared credentials file and attaches AdministratorAccess to
# the starting user.

# Scenario-specific starting user with privilege escalation permissions
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-gamelift-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-gamelift-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+gamelift-createbuild+gamelift-createfleet"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Admin role (target of privilege escalation)
# This role trusts gamelift.amazonaws.com so it can be used as an instance role for GameLift fleets
resource "aws_iam_role" "admin_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-gamelift-001-to-admin-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "gamelift.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-gamelift-001-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+gamelift-createbuild+gamelift-createfleet"
    Purpose     = "admin-target"
  }
}

# Attach administrator access to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Policy attached directly to the starting user granting privilege escalation permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-gamelift-001-to-admin-starting-user-policy"
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
        Resource = aws_iam_role.admin_role.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "gamelift.amazonaws.com"
          }
        }
      },
      {
        Sid    = "RequiredForExploitationGameLift"
        Effect = "Allow"
        Action = [
          "gamelift:CreateBuild",
          "gamelift:CreateFleet",
          "gamelift:RequestUploadCredentials"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "gamelift:DescribeBuild",
          "gamelift:DescribeFleetAttributes",
          "gamelift:ListFleets",
          "gamelift:DescribeInstances",
          "gamelift:GetComputeAccess",
          "iam:ListAttachedUserPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions. AdministratorAccess grants ssm:GetParameter
# implicitly, so no additional IAM wiring is needed beyond what the exploit already produces.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/gamelift-001-to-admin"
  description = "CTF flag for the gamelift-001 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-gamelift-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+gamelift-createbuild+gamelift-createfleet"
    Purpose     = "ctf-flag"
  }
}
