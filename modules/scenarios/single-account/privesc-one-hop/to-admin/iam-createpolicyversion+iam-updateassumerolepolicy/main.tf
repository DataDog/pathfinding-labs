# IAM CreatePolicyVersion + UpdateAssumeRolePolicy privilege escalation to admin scenario
#
# This scenario demonstrates how a user with iam:CreatePolicyVersion on a customer-managed
# policy attached to a role, combined with iam:UpdateAssumeRolePolicy on that role, can:
# 1. Create a new policy version with admin permissions
# 2. Update the role's trust policy to allow themselves to assume it
# 3. Assume the role to gain admin access
#
# CRITICAL: The starting user does NOT have sts:AssumeRole permission initially.
# When the trust policy is updated to explicitly name the starting user ARN,
# AWS allows that user to assume the role without requiring sts:AssumeRole in their IAM policy.

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-cpvuar-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-cpvuar-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-createpolicyversion+iam-updateassumerolepolicy"
    Purpose     = "starting-user"
  }
}

# Access key for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting the exploitable permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-cpvuar-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredPermissions"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicyVersion"
        ]
        Resource = aws_iam_policy.target_policy.arn
      },
      {
        Sid    = "RequiredPermissions2"
        Effect = "Allow"
        Action = [
          "iam:UpdateAssumeRolePolicy"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "HelpfulAdditionalPermissions"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:GetUser",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:ListRoles",
          "iam:GetRole"
        ]
        Resource = "*"
      }
    ]
  })
}

# Customer-managed policy that will be attached to the target role
# Initially has minimal permissions, but can be escalated via CreatePolicyVersion
resource "aws_iam_policy" "target_policy" {
  provider    = aws.prod
  name        = "pl-prod-cpvuar-to-admin-target-policy"
  description = "Policy attached to target role - can be escalated via CreatePolicyVersion"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MinimalPermissions"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-cpvuar-to-admin-target-policy"
    Environment = var.environment
    Scenario    = "iam-createpolicyversion+iam-updateassumerolepolicy"
    Purpose     = "target-policy"
  }
}

# Target role that has the customer-managed policy attached
# Initially trusts only EC2 service, but can be escalated via UpdateAssumeRolePolicy
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-cpvuar-to-admin-target-role"

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
    Name        = "pl-prod-cpvuar-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-createpolicyversion+iam-updateassumerolepolicy"
    Purpose     = "admin-target"
  }
}

# Attach the customer-managed policy to the target role
resource "aws_iam_role_policy_attachment" "target_role_custom_policy" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = aws_iam_policy.target_policy.arn
}
