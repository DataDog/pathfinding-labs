terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + datapipeline privilege escalation scenario
#
# This scenario demonstrates how an attacker with iam:PassRole and datapipeline permissions
# can escalate privileges to administrator by creating a Data Pipeline that executes commands
# with an admin role, then using that to attach AdministratorAccess to themselves.

# Resource naming convention: pl-prod-datapipeline-001-to-admin-{resource-type}
# Provider: aws.prod (single account scenario)

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-datapipeline-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-datapipeline-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+datapipeline-pipeline"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (PassRole + Data Pipeline permissions)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-datapipeline-001-to-admin-starting-user-policy"
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
        Resource = aws_iam_role.pipeline_role.arn
      },
      {
        Sid    = "RequiredForExploitationDataPipeline"
        Effect = "Allow"
        Action = [
          "datapipeline:CreatePipeline",
          "datapipeline:PutPipelineDefinition",
          "datapipeline:ActivatePipeline"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "datapipeline:DescribePipelines",
          "datapipeline:GetPipelineDefinition",
          "iam:ListRoles",
          "iam:GetUser"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin role that will be passed to Data Pipeline
resource "aws_iam_role" "pipeline_role" {
  provider = aws.prod
  name     = "pl-prod-datapipeline-001-to-admin-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "datapipeline.amazonaws.com",
            "elasticmapreduce.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-datapipeline-001-to-admin-pipeline-role"
    Environment = var.environment
    Scenario    = "iam-passrole+datapipeline-pipeline"
    Purpose     = "pipeline-role-with-admin-access"
  }
}

# Attach AdministratorAccess to the pipeline role
resource "aws_iam_role_policy_attachment" "pipeline_role_policy" {
  provider   = aws.prod
  role       = aws_iam_role.pipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/datapipeline-001-to-admin"
  description = "CTF flag for the datapipeline-001 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-datapipeline-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+datapipeline-pipeline"
    Purpose     = "ctf-flag"
  }
}
