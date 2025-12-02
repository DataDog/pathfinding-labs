# iam:PassRole + lambda:CreateFunction + lambda:AddPermission privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, lambda:CreateFunction,
# lambda:AddPermission, and lambda:InvokeFunction can create a new Lambda function
# with an admin role, add permission to invoke it, and execute malicious code to
# gain admin access

# Resource naming convention: pl-prod-iprlcflap-to-admin-{resource-type}
# All resources use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-iprlcflap-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-iprlcflap-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+lambda-addpermission"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with required and helpful permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iprlcflap-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "requiredPermissions1"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-iprlcflap-to-admin-target-role"
      },
      {
        Sid    = "requiredPermissions2"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:AddPermission"
        ]
        Resource = "*"
      },
      {
        Sid    = "requiredPermissions3"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions1"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "lambda:GetFunction",
          "lambda:GetPolicy",
          "lambda:DeleteFunction"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target admin role (target of privilege escalation)
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-iprlcflap-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-iprlcflap-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+lambda-addpermission"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess policy to target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
