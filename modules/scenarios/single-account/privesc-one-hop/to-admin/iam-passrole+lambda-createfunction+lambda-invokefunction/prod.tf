terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-one-hop-plcflif-starting-user"

  tags = {
    Name        = "pl-prod-one-hop-plcflif-starting-user"
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

# Minimal policy for the starting user (just enough to assume the role)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-one-hop-plcflif-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-one-hop-plcflif-role"
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

# Admin role (target of privilege escalation)
# Trusts lambda.amazonaws.com so it can be passed to Lambda functions
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-plcflif-admin-role"

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
    Name        = "pl-prod-one-hop-plcflif-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+lambda-invokefunction"
    Purpose     = "admin-target"
  }
}

# Attach administrator access to the admin role
resource "aws_iam_role_policy_attachment" "admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Role that can PassRole and manage Lambda functions (privilege escalation vector)
resource "aws_iam_role" "privesc_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-plcflif-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.starting_user.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-one-hop-plcflif-role"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+lambda-invokefunction"
    Purpose     = "vulnerable-role"
  }
}

# Policy that allows PassRole on the admin role and Lambda operations
resource "aws_iam_policy" "privesc_policy" {
  provider    = aws.prod
  name        = "pl-prod-one-hop-passrole-lambda-policy"
  description = "Allows PassRole on admin role and creating/invoking Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.admin_role.arn
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
          "lambda:InvokeFunction",
          "lambda:GetFunction",
          "iam:GetRole"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-one-hop-passrole-lambda-policy"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+lambda-invokefunction"
  }
}

# Attach the policy to the privilege escalation role
resource "aws_iam_role_policy_attachment" "privesc_policy_attachment" {
  provider   = aws.prod
  role       = aws_iam_role.privesc_role.name
  policy_arn = aws_iam_policy.privesc_policy.arn
}
