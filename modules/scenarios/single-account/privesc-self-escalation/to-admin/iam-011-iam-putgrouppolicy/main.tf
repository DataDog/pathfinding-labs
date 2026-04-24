terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Group that will be escalated
resource "aws_iam_group" "target_group" {
  provider = aws.prod
  name     = "pl-prod-iam-011-to-admin-escalation-group"
}

# Create the user that will perform self-escalation
resource "aws_iam_user" "privesc_user" {
  provider = aws.prod
  name     = "pl-prod-iam-011-to-admin-paul"

  tags = {
    Name        = "pl-prod-iam-011-to-admin-paul"
    Environment = var.environment
    Scenario    = "iam-011-iam-putgrouppolicy"
    Purpose     = "self-escalation-user"
  }
}

# Add the user to the group
resource "aws_iam_group_membership" "group_membership" {
  provider = aws.prod
  name     = "pl-prod-iam-011-to-admin-group-membership"

  users = [
    aws_iam_user.privesc_user.name
  ]

  group = aws_iam_group.target_group.name
}

# Create access key for the privesc user
resource "aws_iam_access_key" "privesc_user_key" {
  provider = aws.prod
  user     = aws_iam_user.privesc_user.name
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# an inline policy granting Action:* on Resource:* provides the required permission.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/iam-011-to-admin"
  description = "CTF flag for the iam-011 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-iam-011-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-putgrouppolicy"
    Purpose     = "ctf-flag"
  }
}

# Policy that allows the user to put group policies (the vulnerability)
resource "aws_iam_user_policy" "privesc_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-011-to-admin-putgrouppolicy"
  user     = aws_iam_user.privesc_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPutGroupPolicy"
        Effect = "Allow"
        Action = [
          "iam:PutGroupPolicy"
        ]
        Resource = aws_iam_group.target_group.arn
      }
    ]
  })
}