terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + lambda:CreateFunction + lambda:AddPermission privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, lambda:CreateFunction,
# lambda:AddPermission, and lambda:InvokeFunction can create a new Lambda function
# with an admin role, add permission to invoke it, and execute malicious code to
# gain admin access

# Resource naming convention: pl-prod-lambda-006-to-admin-{resource-type}
# All resources use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-lambda-006-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-lambda-006-to-admin-starting-user"
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
  name     = "pl-prod-lambda-006-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-lambda-006-to-admin-target-role"
      },
      {
        Sid    = "RequiredForExploitationLambda"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:AddPermission",
          "lambda:InvokeFunction"
        ]
        Resource = "*"
      },
      {
        Sid    = "RequiredForExploitationIdentity"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target admin role (target of privilege escalation)
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-lambda-006-to-admin-target-role"

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
    Name        = "pl-prod-lambda-006-to-admin-target-role"
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

resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/lambda-006-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name     = "pl-prod-lambda-006-to-admin-flag"
    Scenario = "lambda-006-iam-passrole+lambda-createfunction+lambda-addpermission"
    Purpose  = "ctf-flag"
  }
}
