# PassRole + Lambda CreateFunction + InvokeFunction privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, lambda:CreateFunction,
# and lambda:InvokeFunction can escalate to admin by creating a Lambda function
# with an admin execution role and invoking it to extract temporary credentials.

# Resource naming convention: pl-prod-plcflif-to-admin-{resource-type}
# plcflif = PassRole + Lambda CreateFunction + Lambda InvokeFunction

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Scenario-specific starting user with privilege escalation permissions
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-plcflif-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-plcflif-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+lambda-invokefunction"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Admin role (target of privilege escalation)
# This role trusts lambda.amazonaws.com so it can be passed to Lambda functions
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-plcflif-to-admin-target-role"

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
    Name        = "pl-prod-plcflif-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+lambda-invokefunction"
    Purpose     = "admin-target"
  }
}

# Attach administrator access to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Policy attached directly to the starting user granting privilege escalation permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-plcflif-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "lambda.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:InvokeFunction"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:GetRole",
          "iam:ListRoles",
          "lambda:GetFunction",
          "lambda:DeleteFunction"
        ]
        Resource = "*"
      }
    ]
  })
}
