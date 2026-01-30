terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# SageMaker UpdateNotebook Lifecycle Config privilege escalation scenario
#
# This scenario demonstrates how a user with SageMaker update permissions can inject
# a malicious lifecycle configuration into an existing notebook instance to execute
# code with the notebook's admin execution role.

# Resource naming convention: pl-prod-sagemaker-005-to-admin-{resource-type}
# sagemaker-005 = SageMaker UpdateNotebook Lifecycle Config (pathfinding.cloud ID)

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-sagemaker-005-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-sagemaker-005-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "sagemaker-updatenotebook-lifecycle-config"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting SageMaker update permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-sagemaker-005-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "requiredPermissions1"
        Effect = "Allow"
        Action = [
          "sagemaker:CreateNotebookInstanceLifecycleConfig"
        ]
        Resource = "*"
      },
      {
        Sid    = "requiredPermissions2"
        Effect = "Allow"
        Action = [
          "sagemaker:StopNotebookInstance",
          "sagemaker:UpdateNotebookInstance",
          "sagemaker:StartNotebookInstance"
        ]
        Resource = "arn:aws:sagemaker:*:${var.account_id}:notebook-instance/pl-prod-sagemaker-005-to-admin-notebook"
      },
      {
        Sid    = "helpfulAdditionalPermissions1"
        Effect = "Allow"
        Action = [
          "sagemaker:DescribeNotebookInstance",
          "sagemaker:ListNotebookInstances",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions2"
        Effect = "Allow"
        Action = [
          "iam:GetRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions3"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Notebook execution role (target admin role)
resource "aws_iam_role" "notebook_execution_role" {
  provider = aws.prod
  name     = "pl-prod-sagemaker-005-to-admin-notebook-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "sagemaker.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-sagemaker-005-to-admin-notebook-role"
    Environment = var.environment
    Scenario    = "sagemaker-updatenotebook-lifecycle-config"
    Purpose     = "notebook-execution-role"
  }
}

# Attach AdministratorAccess to the notebook execution role
resource "aws_iam_role_policy_attachment" "notebook_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.notebook_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# SageMaker Notebook Instance (vulnerable target)
resource "aws_sagemaker_notebook_instance" "target_notebook" {
  provider      = aws.prod
  name          = "pl-prod-sagemaker-005-to-admin-notebook"
  role_arn      = aws_iam_role.notebook_execution_role.arn
  instance_type = "ml.t3.medium"

  # Enable direct internet access and root access
  direct_internet_access = "Enabled"
  root_access            = "Enabled"

  # No lifecycle config initially - attacker will inject one
  lifecycle_config_name = null

  tags = {
    Name        = "pl-prod-sagemaker-005-to-admin-notebook"
    Environment = var.environment
    Scenario    = "sagemaker-updatenotebook-lifecycle-config"
    Purpose     = "vulnerable-notebook"
  }
}
