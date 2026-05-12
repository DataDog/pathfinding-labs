terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Scenario-specific starting user with PutUserPolicy permission on itself
resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-iam-007-to-admin-starting-user"
}

# Create access key for the user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Inline policy allowing the user to put inline policies on itself
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-007-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPutUserPolicy"
        Effect = "Allow"
        Action = [
          "iam:PutUserPolicy"
        ]
        Resource = aws_iam_user.starting_user.arn
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:GetUser",
          "iam:ListUserPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# CTF flag stored in SSM Parameter Store. Readable by any principal with ssm:GetParameter on
# this parameter — in practice this means any admin-equivalent principal, since the inline
# admin policy granting Action:* on Resource:* provides the required permission.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/iam-007-to-admin"
  description = "CTF flag for the iam-007 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name     = "pl-prod-iam-007-to-admin-flag"
    Scenario = "iam-putuserpolicy"
    Purpose  = "ctf-flag"
  }
}