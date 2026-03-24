terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# SageMaker CreatePresignedNotebookInstanceUrl privilege escalation scenario
#
# This scenario demonstrates how a user with sagemaker:CreatePresignedNotebookInstanceUrl
# can generate a presigned URL to access an existing SageMaker notebook instance that has
# an admin execution role, then use the Jupyter terminal to execute commands with elevated privileges.

# Resource naming convention: pl-{environment}-{path-id}-{resource-type}
# Path ID: sagemaker-004 (from pathfinding.cloud)

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-${var.environment}-sagemaker-004-to-admin-starting-user"

  tags = {
    Name        = "pl-${var.environment}-sagemaker-004-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "sagemaker-createpresignednotebookinstanceurl"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with CreatePresignedNotebookInstanceUrl and discovery permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-${var.environment}-sagemaker-004-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationCreatePresignedUrl"
        Effect = "Allow"
        Action = [
          "sagemaker:CreatePresignedNotebookInstanceUrl"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin execution role for the notebook instance (target)
resource "aws_iam_role" "notebook_execution_role" {
  provider = aws.prod
  name     = "pl-${var.environment}-sagemaker-004-to-admin-notebook-role"

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
    Name        = "pl-${var.environment}-sagemaker-004-to-admin-notebook-role"
    Environment = var.environment
    Scenario    = "sagemaker-createpresignednotebookinstanceurl"
    Purpose     = "notebook-execution-role"
  }
}

# Attach AdministratorAccess to the notebook execution role
resource "aws_iam_role_policy_attachment" "notebook_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.notebook_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create the existing SageMaker notebook instance with admin role
resource "aws_sagemaker_notebook_instance" "target_notebook" {
  provider               = aws.prod
  name                   = "pl-${var.environment}-sagemaker-004-to-admin-notebook"
  role_arn               = aws_iam_role.notebook_execution_role.arn
  instance_type          = "ml.t3.medium"
  direct_internet_access = "Enabled"

  tags = {
    Name        = "pl-${var.environment}-sagemaker-004-to-admin-notebook"
    Environment = var.environment
    Scenario    = "sagemaker-createpresignednotebookinstanceurl"
    Purpose     = "target-notebook"
  }
}
