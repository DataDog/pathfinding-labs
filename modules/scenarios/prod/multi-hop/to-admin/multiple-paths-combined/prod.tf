terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
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
          AWS = "arn:aws:iam::${var.prod_account_id}:user/pl-pathfinder-starting-user-prod"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
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
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "lambda:CreateFunction",
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration",
          "cloudformation:CreateStack",
          "cloudformation:DescribeStacks",
          "ec2:RunInstances",
          "ec2:DescribeImages",
          "ec2:CreateTags",
          "iam:CreateLoginProfile"
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
