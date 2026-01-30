terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# CloudFormation CreateChangeSet+ExecuteChangeSet privilege escalation scenario
#
# This scenario demonstrates how a principal with cloudformation:CreateChangeSet and
# cloudformation:ExecuteChangeSet permissions can inherit administrative permissions
# from an existing CloudFormation stack's service role by creating and executing a
# change set that modifies the stack to create privileged resources.

# Resource naming convention: pl-prod-cloudformation-005-to-admin-{resource-type}
# All resources use provider = aws.prod (single account scenario)

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-005-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-cloudformation-005-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "cloudformation-createchangeset+executechangeset"
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
  name     = "pl-prod-cloudformation-005-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "requiredPermissions1"
        Effect = "Allow"
        Action = [
          "cloudformation:CreateChangeSet"
        ]
        Resource = "*"
      },
      {
        Sid    = "requiredPermissions2"
        Effect = "Allow"
        Action = [
          "cloudformation:ExecuteChangeSet"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions1"
        Effect = "Allow"
        Action = [
          "cloudformation:DescribeChangeSet"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions2"
        Effect = "Allow"
        Action = [
          "cloudformation:DescribeStacks"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions3"
        Effect = "Allow"
        Action = [
          "cloudformation:DescribeStackResource",
          "cloudformation:GetTemplate"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions4"
        Effect = "Allow"
        Action = [
          "iam:GetRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions5"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-cloudformation-005-to-admin-escalated-role"
      }
    ]
  })
}

# CloudFormation stack service role with administrative access
resource "aws_iam_role" "stack_role" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-005-to-admin-stack-role"

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
    Name        = "pl-prod-cloudformation-005-to-admin-stack-role"
    Environment = var.environment
    Scenario    = "cloudformation-createchangeset+executechangeset"
    Purpose     = "stack-service-role"
  }
}

# Attach AdministratorAccess to the stack service role
resource "aws_iam_role_policy_attachment" "stack_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.stack_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CloudFormation stack with an initial simple template
# This stack uses the admin service role and can be modified via change sets
resource "aws_cloudformation_stack" "target_stack" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-005-to-admin-target-stack"

  iam_role_arn = aws_iam_role.stack_role.arn

  # Wait for policy attachment to propagate
  depends_on = [aws_iam_role_policy_attachment.stack_role_admin_access]

  # Initial template creates a simple S3 bucket
  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "Initial CloudFormation stack for privilege escalation scenario"
    Resources = {
      InitialBucket = {
        Type = "AWS::S3::Bucket"
        Properties = {
          BucketName = "pl-prod-cloudformation-005-to-admin-initial-bucket-${var.account_id}-${var.resource_suffix}"
          Tags = [
            {
              Key   = "Name"
              Value = "pl-prod-cloudformation-005-to-admin-initial-bucket"
            },
            {
              Key   = "Environment"
              Value = var.environment
            },
            {
              Key   = "Scenario"
              Value = "cloudformation-createchangeset+executechangeset"
            },
            {
              Key   = "Purpose"
              Value = "initial-stack-resource"
            }
          ]
        }
      }
    }
    Outputs = {
      BucketName = {
        Description = "Name of the S3 bucket"
        Value = {
          Ref = "InitialBucket"
        }
      }
    }
  })

  tags = {
    Name        = "pl-prod-cloudformation-005-to-admin-target-stack"
    Environment = var.environment
    Scenario    = "cloudformation-createchangeset+executechangeset"
    Purpose     = "target-cloudformation-stack"
  }
}
