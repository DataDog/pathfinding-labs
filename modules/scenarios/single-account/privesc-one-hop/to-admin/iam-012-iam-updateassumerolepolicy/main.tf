terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# IAM UpdateAssumeRolePolicy privilege escalation to admin scenario
#
# This scenario demonstrates how a user with iam:UpdateAssumeRolePolicy permission
# can modify the trust policy of an admin role to grant themselves access.

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-iam-012-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iam-012-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-012-iam-updateassumerolepolicy"
    Purpose     = "starting-user"
  }
}

# Access key for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting UpdateAssumeRolePolicy permission on the target role
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-012-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationUpdateAssumeRolePolicy"
        Effect = "Allow"
        Action = [
          "iam:UpdateAssumeRolePolicy"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "RequiredForExploitationAssumeRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target admin role that the attacker will modify the trust policy of
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-iam-012-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com" # Initially trusts only EC2 service
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-iam-012-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-012-iam-updateassumerolepolicy"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CTF flag stored in SSM Parameter Store — readable only after gaining admin access
resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/iam-012-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name        = "pl-prod-iam-012-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-012-iam-updateassumerolepolicy"
    Purpose     = "ctf-flag"
  }
}
