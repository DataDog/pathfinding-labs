# IAM UpdateLoginProfile privilege escalation to admin scenario
#
# This scenario demonstrates how a user with iam:UpdateLoginProfile permission
# can escalate to administrative privileges by changing the console password
# of an existing admin user who already has a login profile.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-iam-006-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iam-006-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-updateloginprofile"
    Purpose     = "starting-user"
  }
}

# Access key for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy that allows updating login profiles for the admin user (privilege escalation vector)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-006-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationUpdateLoginProfile"
        Effect = "Allow"
        Action = [
          "iam:UpdateLoginProfile"
        ]
        Resource = "arn:aws:iam::${var.account_id}:user/pl-prod-iam-006-to-admin-target-user"
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "iam:ListUsers",
          "iam:GetUser",
          "iam:GetLoginProfile"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin user that will be the target of privilege escalation
# This user has AdministratorAccess AND an existing console password (login profile)
resource "aws_iam_user" "admin_user" {
  provider = aws.prod
  name     = "pl-prod-iam-006-to-admin-target-user"

  tags = {
    Name        = "pl-prod-iam-006-to-admin-target-user"
    Environment = var.environment
    Scenario    = "iam-updateloginprofile"
    Purpose     = "target-admin-user"
  }
}

# Attach AdministratorAccess to the admin user
resource "aws_iam_user_policy_attachment" "admin_access" {
  provider   = aws.prod
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create an existing login profile for the admin user
# This represents a pre-existing console password that the attacker will update
resource "aws_iam_user_login_profile" "admin_login_profile" {
  provider                = aws.prod
  user                    = aws_iam_user.admin_user.name
  password_reset_required = false

  lifecycle {
    ignore_changes = [
      password_length,
      password_reset_required,
      pgp_key
    ]
  }
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/iam-006-to-admin"
  description = "CTF flag for the iam-006 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-iam-006-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-updateloginprofile"
    Purpose     = "ctf-flag"
  }
}
