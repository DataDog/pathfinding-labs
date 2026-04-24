terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam-putrolepolicy+iam-updateassumerolepolicy privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PutRolePolicy and iam:UpdateAssumeRolePolicy
# can modify a role's inline policy to grant admin access, update the role's trust policy to
# allow themselves to assume it, and then assume the role to gain admin privileges.
#
# CRITICAL: The starting user does NOT need sts:AssumeRole permission in their IAM policy.
# When the trust policy explicitly names the user ARN, AWS allows that user to assume the role
# without requiring sts:AssumeRole permission in the user's policy.

# Resource naming convention: pl-prod-iam-021-to-admin-{resource-type}
# iam-021 = pathfinding.cloud ID for iam:PutRolePolicy + iam:UpdateAssumeRolePolicy

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-iam-021-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iam-021-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-putrolepolicy+iam-updateassumerolepolicy"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting the exploitable permissions
# CRITICAL: This user does NOT have sts:AssumeRole permission
# They don't need it because updating the trust policy to name them explicitly allows assumption
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-021-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPutRolePolicyUpdateAssumeRolePolicy"
        Effect = "Allow"
        Action = [
          "iam:PutRolePolicy",
          "iam:UpdateAssumeRolePolicy"
        ]
        Resource = aws_iam_role.target_role.arn
      }
    ]
  })
}

# Target role that will be modified to grant admin access
# CRITICAL: Initial trust policy does NOT trust the starting user
# This makes it a true attack - the user must modify the trust policy first
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-iam-021-to-admin-target-role"

  # Initial trust policy that does NOT trust the starting user
  # The attack involves updating this to add the starting user
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # Trust root initially (simulating a role for some other purpose)
        AWS = "arn:aws:iam::${var.account_id}:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          # Add a condition that no principal in the account satisfies initially
          # This effectively makes the role unassumable until trust policy is updated
          "aws:username" = "nonexistent-user-placeholder"
        }
      }
    }]
  })

  tags = {
    Name        = "pl-prod-iam-021-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-putrolepolicy+iam-updateassumerolepolicy"
    Purpose     = "target-role"
  }
}

# The role starts with NO inline policies
# The attack involves using iam:PutRolePolicy to add an admin policy
# We intentionally don't create any initial policies here

# Note: In a real attack scenario, this role might have some benign initial permissions
# or be intended for some other purpose. The attacker discovers they can modify it
# and uses that to escalate privileges.

resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/iam-021-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name     = "pl-prod-iam-021-to-admin-flag"
    Scenario = "iam-021-iam-putrolepolicy+iam-updateassumerolepolicy"
    Purpose  = "ctf-flag"
  }
}
