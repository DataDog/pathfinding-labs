terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.dev, aws.prod]
    }
  }
}

# Dev to Prod Cross-Account Role Chain to Admin scenario
#
# This scenario demonstrates how a non-admin dev user can chain through a dev
# role and two prod roles via sts:AssumeRole alone to reach prod administrative
# access — no IAM modifications, no compute services, pure role chaining.

# Scenario-specific starting user in the dev account
# force_destroy = true lets Terraform clean up any policies, access keys,
# login profiles, or group memberships the demo attaches out-of-band so
# destroy still succeeds if the user disables the scenario without first
# running cleanup_attack.sh.
resource "aws_iam_user" "starting_user" {
  provider      = aws.dev
  force_destroy = true
  name          = "pl-dev-sts-role-chain-starting-user"

  tags = {
    Name        = "pl-dev-sts-role-chain-starting-user"
    Environment = "dev"
    Scenario    = "sts-role-chain"
    Purpose     = "starting-user"
  }
}

# Access key for the starting user — read by demo scripts via Terraform outputs
resource "aws_iam_access_key" "starting_user" {
  provider = aws.dev
  user     = aws_iam_user.starting_user.name
}

# Minimal inline policy: the starting user only needs sts:AssumeRole on the dev role
resource "aws_iam_user_policy" "starting_user" {
  provider = aws.dev
  name     = "pl-dev-sts-role-chain-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationAssumeRole"
        Effect = "Allow"
        Action = ["sts:AssumeRole"]
        Resource = "arn:aws:iam::${var.dev_account_id}:role/pl-dev-sts-role-chain-dev-role"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
        ]
        Resource = "*"
      }
    ]
  })
}

# Dev role that the starting user assumes as the first hop.
# force_detach_policies = true is the role equivalent of force_destroy on
# aws_iam_user: it lets Terraform detach managed policies the demo may
# attach out-of-band so destroy succeeds without a prior cleanup run.
resource "aws_iam_role" "dev_role" {
  provider              = aws.dev
  force_detach_policies = true
  name                  = "pl-dev-sts-role-chain-dev-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStartingUserToAssume"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.dev_account_id}:user/pl-dev-sts-role-chain-starting-user"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-dev-sts-role-chain-dev-role"
    Environment = "dev"
    Scenario    = "sts-role-chain"
    Purpose     = "dev-hop-role"
  }
}

# Inline policy for the dev role: grants cross-account AssumeRole into prod
# plus helpful recon permissions.
resource "aws_iam_role_policy" "dev_role" {
  provider = aws.dev
  name     = "pl-dev-sts-role-chain-dev-role-policy"
  role     = aws_iam_role.dev_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationAssumeRole"
        Effect = "Allow"
        Action = ["sts:AssumeRole"]
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-sts-role-chain-prod-non-admin-role"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:ListRoles",
        ]
        Resource = "*"
      }
    ]
  })
}
