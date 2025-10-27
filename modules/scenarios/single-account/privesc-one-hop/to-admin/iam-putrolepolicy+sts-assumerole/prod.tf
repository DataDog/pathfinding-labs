# PutRolePolicy + AssumeRole privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PutRolePolicy and sts:AssumeRole
# permissions on a target role can escalate privileges by adding an inline admin
# policy to that role, then assuming it to gain administrative access.

# Resource naming convention: pl-prod-prpsar-to-admin-{resource-type}
# prpsar = PutRolePolicy + AssumeRole

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-prpsar-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-prpsar-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-putrolepolicy+sts-assumerole"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with exploit permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-prpsar-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredPermissions"
        Effect = "Allow"
        Action = [
          "iam:PutRolePolicy",
          "sts:AssumeRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "HelpfulPermissions"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:GetRolePolicy"
        ]
        Resource = "*"
      },
      {
        Sid    = "StandardPermissions"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target role (initially has minimal permissions)
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-prpsar-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = aws_iam_user.starting_user.arn
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-prpsar-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-putrolepolicy+sts-assumerole"
    Purpose     = "target-role"
  }
}

# Minimal read-only policy for the target role (initially no admin access)
resource "aws_iam_role_policy" "target_role_initial_policy" {
  provider = aws.prod
  name     = "pl-prod-prpsar-to-admin-target-role-initial-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MinimalReadAccess"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:GetUser",
          "iam:GetRole"
        ]
        Resource = "*"
      }
    ]
  })
}
