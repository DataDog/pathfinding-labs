# CreatePolicyVersion + AssumeRole privilege escalation scenario
#
# This scenario demonstrates how a user with iam:CreatePolicyVersion on a customer-managed policy
# attached to a role can create a new policy version with admin permissions, then assume that role
# to gain administrative access.

# Resource naming convention: pl-prod-cpvsar-to-admin-{resource-type}
# Shorthand: cpvsar = CreatePolicyVersion+AssumeRole

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-cpvsar-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-cpvsar-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-createpolicyversion+sts-assumerole"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Customer-managed policy with minimal permissions (will be modified by attack)
resource "aws_iam_policy" "target_policy" {
  provider    = aws.prod
  name        = "pl-prod-cpvsar-to-admin-target-policy"
  description = "Customer-managed policy attached to target role (initial version has minimal permissions)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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

  tags = {
    Name        = "pl-prod-cpvsar-to-admin-target-policy"
    Environment = var.environment
    Scenario    = "iam-createpolicyversion+sts-assumerole"
    Purpose     = "target-policy"
  }
}

# Target role that will gain admin permissions via policy version update
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-cpvsar-to-admin-target-role"

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
    Name        = "pl-prod-cpvsar-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-createpolicyversion+sts-assumerole"
    Purpose     = "target-role"
  }
}

# Attach customer-managed policy to target role
resource "aws_iam_role_policy_attachment" "target_role_policy" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = aws_iam_policy.target_policy.arn
}

# Starting user policy granting exploitable permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-cpvsar-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreatePolicyVersion"
        ]
        Resource = aws_iam_policy.target_policy.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:ListRoles",
          "iam:GetRole"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}
