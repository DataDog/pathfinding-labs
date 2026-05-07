terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# CloudFormation UpdateStack privilege escalation scenario
#
# This scenario demonstrates how a user with cloudformation:UpdateStack permission
# can modify an existing CloudFormation stack that uses an administrative service role
# to create a new escalated role, which they can then assume for full admin access.

# Resource naming convention: pl-prod-cloudformation-002-to-admin-{resource-type}
# All resources use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-cloudformation-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "cloudformation-updatestack"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user - can update the CloudFormation stack and assume escalated role
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-002-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationUpdateStack"
        Effect = "Allow"
        Action = [
          "cloudformation:UpdateStack"
        ]
        Resource = "arn:aws:cloudformation:*:${var.account_id}:stack/pl-prod-cloudformation-002-to-admin-stack/*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "cloudformation:DescribeStacks",
          "cloudformation:GetTemplate",
          "iam:GetRole"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudFormation stack service role with administrative permissions
resource "aws_iam_role" "stack_role" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-002-to-admin-stack-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudformation.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-cloudformation-002-to-admin-stack-role"
    Environment = var.environment
    Scenario    = "cloudformation-updatestack"
    Purpose     = "stack-service-role"
  }
}

# Attach AdministratorAccess to the stack service role
resource "aws_iam_role_policy_attachment" "stack_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.stack_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CloudFormation stack with benign initial template
resource "aws_cloudformation_stack" "vulnerable_stack" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-002-to-admin-stack"

  # Use the administrative service role
  iam_role_arn = aws_iam_role.stack_role.arn

  # Required because the stack (or its current state after demo runs) contains IAM named resources
  capabilities = ["CAPABILITY_NAMED_IAM"]

  # Wait for policy attachment to propagate
  depends_on = [aws_iam_role_policy_attachment.stack_role_admin_access]

  # Ignore changes to template_body since demo/cleanup scripts modify the stack
  lifecycle {
    ignore_changes = [template_body]
  }

  # Initial benign template - creates a simple S3 bucket
  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "Initial benign template for CloudFormation UpdateStack scenario"
    Resources = {
      InitialBucket = {
        Type = "AWS::S3::Bucket"
        Properties = {
          BucketName = "pl-cfn-002-admin-bucket-${var.account_id}-${var.resource_suffix}"
          Tags = [
            {
              Key   = "Name"
              Value = "pl-cfn-002-admin-bucket"
            },
            {
              Key   = "Environment"
              Value = var.environment
            },
            {
              Key   = "Scenario"
              Value = "cloudformation-updatestack"
            },
            {
              Key   = "Purpose"
              Value = "initial-benign-resource"
            }
          ]
        }
      }
    }
    Outputs = {
      BucketName = {
        Description = "Name of the initial S3 bucket"
        Value = {
          Ref = "InitialBucket"
        }
      }
    }
  })

  tags = {
    Name        = "pl-prod-cloudformation-002-to-admin-stack"
    Environment = var.environment
    Scenario    = "cloudformation-updatestack"
    Purpose     = "vulnerable-stack"
  }
}

# CTF flag stored in SSM Parameter Store.
# Retrieving it requires administrator-equivalent permissions (ssm:GetParameter is
# granted implicitly by AdministratorAccess). The escalated role assumed at the end
# of the attack path provides the necessary access.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/cloudformation-002-to-admin"
  description = "CTF flag for the cloudformation-002 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-cloudformation-002-to-admin-flag"
    Environment = var.environment
    Scenario    = "cloudformation-updatestack"
    Purpose     = "ctf-flag"
  }
}
