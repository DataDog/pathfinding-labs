terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + cloudformation:CreateStackSet + cloudformation:CreateStackInstances privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and cloudformation:CreateStackSet
# can escalate privileges by creating a StackSet that passes an execution role with admin
# permissions to CloudFormation, which then creates a new IAM role with admin access.

# Resource naming convention: pl-prod-cloudformation-003-to-admin-{resource-type}
# cloudformation-003 = pathfinding.cloud ID for this scenario

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-003-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-cloudformation-003-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+cloudformation-createstackset+cloudformation-createstackinstances"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with PassRole and CloudFormation StackSet permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-003-to-admin-starting-user-policy"
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
        Resource = [
          aws_iam_role.execution_role.arn,
          aws_iam_role.administration_role.arn
        ]
      },
      {
        Sid    = "RequiredForExploitationCloudFormation"
        Effect = "Allow"
        Action = [
          "cloudformation:CreateStackSet",
          "cloudformation:CreateStackInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "cloudformation:DescribeStackSet",
          "cloudformation:DescribeStackSetOperation",
          "cloudformation:ListStackInstances",
          "cloudformation:DeleteStackInstances",
          "cloudformation:DeleteStackSet",
          "iam:ListRoles",
          "iam:GetRole"
        ]
        Resource = "*"
      }
    ]
  })
}

# StackSet execution role - this is the role that CloudFormation will use to create resources
# It needs admin access to be able to create IAM roles
resource "aws_iam_role" "execution_role" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-003-to-admin-execution-role"

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
          AWS = aws_iam_role.administration_role.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-cloudformation-003-to-admin-execution-role"
    Environment = var.environment
    Scenario    = "iam-passrole+cloudformation-createstackset+cloudformation-createstackinstances"
    Purpose     = "stackset-execution-role"
  }
}

# Attach AdministratorAccess to the execution role so it can create IAM roles
resource "aws_iam_role_policy_attachment" "execution_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# StackSet administration role - required for StackSet operations
resource "aws_iam_role" "administration_role" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-003-to-admin-admin-role"

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
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-cloudformation-003-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+cloudformation-createstackset+cloudformation-createstackinstances"
    Purpose     = "stackset-administration-role"
  }
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/cloudformation-003-to-admin"
  description = "CTF flag for the cloudformation-003 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-cloudformation-003-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+cloudformation-createstackset+cloudformation-createstackinstances"
    Purpose     = "ctf-flag"
  }
}

# Policy for the administration role to assume the execution role
resource "aws_iam_role_policy" "administration_role_policy" {
  provider = aws.prod
  name     = "pl-prod-cloudformation-003-to-admin-admin-role-policy"
  role     = aws_iam_role.administration_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = aws_iam_role.execution_role.arn
      }
    ]
  })
}
