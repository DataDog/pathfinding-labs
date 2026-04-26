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
  name     = "pl-prod-mpc-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-mpc-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "multiple-paths-combined"
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
  name     = "pl-prod-mpc-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationAssumeRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-role-with-multiple-privesc-paths"
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:ListRoles",
          "ec2:DescribeInstances",
          "lambda:ListFunctions"
        ]
        Resource = "*"
      }
    ]
  })
}

# Role with multiple privilege escalation paths
resource "aws_iam_role" "prod_role_with_multiple_privesc_paths" {
  provider = aws.prod
  name     = "pl-prod-role-with-multiple-privesc-paths"

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
    Name        = "pl-prod-role-with-multiple-privesc-paths"
    Environment = var.environment
    Scenario    = "multiple-paths-combined"
    Purpose     = "vulnerable-role"
  }
}

# Policy that allows multiple privilege escalation paths
resource "aws_iam_policy" "prod_privesc_policy_with_multiple_paths" {
  provider    = aws.prod
  name        = "pl-prod-privesc-policy-with-multiple-paths"
  description = "Allows multiple privilege escalation paths"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRoleAndServices"
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "lambda:CreateFunction",
          "lambda:InvokeFunction",
          "cloudformation:CreateStack",
          "ec2:RunInstances",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "lambda:GetFunctionConfiguration",
          "cloudformation:DescribeStacks",
          "ec2:DescribeImages"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "prod_privesc_policy_with_multiple_paths" {
  provider   = aws.prod
  role       = aws_iam_role.prod_role_with_multiple_privesc_paths.name
  policy_arn = aws_iam_policy.prod_privesc_policy_with_multiple_paths.arn
}

# EC2 service role for privilege escalation
resource "aws_iam_role" "prod_ec2_admin_role" {
  provider = aws.prod
  name     = "pl-prod-ec2-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach admin policy to EC2 role
resource "aws_iam_role_policy_attachment" "prod_ec2_admin_role" {
  provider   = aws.prod
  role       = aws_iam_role.prod_ec2_admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Lambda service role for privilege escalation
resource "aws_iam_role" "prod_lambda_admin_role" {
  provider = aws.prod
  name     = "pl-prod-lambda-admin-role"

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
}

# Attach admin policy to Lambda role
resource "aws_iam_role_policy_attachment" "prod_lambda_admin_role" {
  provider   = aws.prod
  role       = aws_iam_role.prod_lambda_admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CloudFormation service role for privilege escalation
resource "aws_iam_role" "prod_cloudformation_admin_role" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudformation.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach admin policy to CloudFormation role
resource "aws_iam_role_policy_attachment" "prod_cloudformation_admin_role" {
  provider   = aws.prod
  role       = aws_iam_role.prod_cloudformation_admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/multiple-paths-combined-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name     = "pl-prod-multiple-paths-combined-to-admin-flag"
    Scenario = "multiple-paths-combined"
    Purpose  = "ctf-flag"
  }
}
