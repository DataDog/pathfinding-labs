terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + CloudFormation UpdateStackSet privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and cloudformation:UpdateStackSet can modify
# an existing StackSet to create an admin role using the StackSet's elevated execution role

# Resource naming convention: pl-prod-cloudformation-004-to-admin-{resource-type}
# cloudformation-004 = Pathfinding.cloud ID for this scenario
# All resources use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-004-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-cloudformation-004-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole-cloudformation-updatestackset"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-004-to-admin-starting-user-policy"
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
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-cloudformation-004-to-admin-stackset-admin-role"
      },
      {
        Sid    = "requiredPermissions2"
        Effect = "Allow"
        Action = [
          "cloudformation:UpdateStackSet"
        ]
        Resource = "arn:aws:cloudformation:*:${var.account_id}:stackset/pl-prod-cloudformation-004-to-admin-stackset:*"
      },
      {
        Sid    = "helpfulAdditionalPermissions"
        Effect = "Allow"
        Action = [
          "cloudformation:DescribeStackSet",
          "cloudformation:DescribeStackSetOperation",
          "cloudformation:GetTemplate",
          "cloudformation:CreateStackInstances",
          "cloudformation:DeleteStackInstances",
          "iam:GetRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "assumeEscalatedRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-cloudformation-004-to-admin-escalated-role"
      },
      {
        Sid    = "getCallerIdentity"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# StackSet Execution Role (with admin permissions - this is what makes the attack possible)
resource "aws_iam_role" "stackset_execution_role" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-004-to-admin-stackset-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudformation.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.stackset_admin_role.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-cloudformation-004-to-admin-stackset-execution-role"
    Environment = var.environment
    Scenario    = "iam-passrole-cloudformation-updatestackset"
    Purpose     = "stackset-execution-role"
  }
}

# Attach AdministratorAccess to execution role (vulnerability: allows creating privileged resources)
resource "aws_iam_role_policy_attachment" "stackset_execution_role_admin" {
  provider   = aws.prod
  role       = aws_iam_role.stackset_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# StackSet Administration Role
resource "aws_iam_role" "stackset_admin_role" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-004-to-admin-stackset-admin-role"

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

  tags = {
    Name        = "pl-prod-cloudformation-004-to-admin-stackset-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole-cloudformation-updatestackset"
    Purpose     = "stackset-admin-role"
  }
}

# Policy for administration role to assume execution role
resource "aws_iam_role_policy" "stackset_admin_role_policy" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-004-to-admin-stackset-admin-policy"
  role     = aws_iam_role.stackset_admin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "iam:PassRole"
        ]
        Resource = aws_iam_role.stackset_execution_role.arn
      }
    ]
  })
}

# Data source to get current region
data "aws_region" "current" {
  provider = aws.prod
}

# CloudFormation StackSet with benign initial template
resource "aws_cloudformation_stack_set" "vulnerable_stackset" {
  provider                = aws.prod
  name                    = "pl-prod-cloudformation-004-to-admin-stackset"
  description             = "Pathfinding Labs - CloudFormation UpdateStackSet privilege escalation scenario"
  permission_model        = "SELF_MANAGED"
  administration_role_arn = aws_iam_role.stackset_admin_role.arn
  execution_role_name     = aws_iam_role.stackset_execution_role.name

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "Benign initial template - creates a simple S3 bucket"
    Resources = {
      BenignBucket = {
        Type = "AWS::S3::Bucket"
        Properties = {
          BucketName = "pl-prod-cloudformation-004-benign-${var.account_id}-${var.resource_suffix}"
          Tags = [
            {
              Key   = "Name"
              Value = "pl-prod-cloudformation-004-benign-bucket"
            },
            {
              Key   = "Environment"
              Value = var.environment
            },
            {
              Key   = "Scenario"
              Value = "cloudformation-updatestackset"
            },
            {
              Key   = "Purpose"
              Value = "benign-initial-resource"
            }
          ]
        }
      }
    }
    Outputs = {
      BucketName = {
        Description = "Name of the benign S3 bucket"
        Value = {
          Ref = "BenignBucket"
        }
      }
    }
  })

  capabilities = ["CAPABILITY_NAMED_IAM"]

  tags = {
    Name        = "pl-prod-cloudformation-004-to-admin-stackset"
    Environment = var.environment
    Scenario    = "iam-passrole-cloudformation-updatestackset"
    Purpose     = "vulnerable-stackset"
  }

  lifecycle {
    ignore_changes = [template_body]
  }
}

# Deploy stack instance to current account and region
resource "aws_cloudformation_stack_set_instance" "stackset_instance" {
  provider       = aws.prod
  stack_set_name = aws_cloudformation_stack_set.vulnerable_stackset.name
  account_id     = var.account_id
  stack_set_instance_region = data.aws_region.current.id

  depends_on = [
    aws_iam_role.stackset_execution_role,
    aws_iam_role.stackset_admin_role,
    aws_iam_role_policy.stackset_admin_role_policy,
    aws_iam_role_policy_attachment.stackset_execution_role_admin
  ]
}
