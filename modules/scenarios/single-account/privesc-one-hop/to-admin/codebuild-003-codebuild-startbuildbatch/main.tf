terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# CodeBuild StartBuildBatch privilege escalation scenario
#
# This scenario demonstrates how a user with codebuild:StartBuildBatch can exploit
# an existing CodeBuild project with a privileged role by using buildspec-override
# to execute arbitrary code with admin permissions.

# Resource naming convention: pl-prod-codebuild-003-to-admin-{resource-type}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-codebuild-003-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-codebuild-003-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "codebuild-startbuildbatch"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user - can start build batches and discover projects
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-codebuild-003-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuildBatch",
          "codebuild:BatchGetBuildBatches",
          "codebuild:ListProjects",
          "codebuild:BatchGetProjects"
        ]
        Resource = "*"
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

# Target role - this is the privileged role attached to the CodeBuild project
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-codebuild-003-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-codebuild-003-to-admin-target-role"
    Environment = var.environment
    Scenario    = "codebuild-startbuildbatch"
    Purpose     = "target-role"
  }
}

# Policy for the target role - includes permissions to grant admin access
resource "aws_iam_role_policy" "target_role_policy" {
  provider = aws.prod
  name     = "pl-prod-codebuild-003-to-admin-target-role-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:AttachUserPolicy"
        ]
        Resource = aws_iam_user.starting_user.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:${var.account_id}:log-group:/aws/codebuild/*"
      }
    ]
  })
}

# Existing CodeBuild project with the privileged role
# This is the pre-existing vulnerable resource that the attacker will exploit
resource "aws_codebuild_project" "target_project" {
  provider = aws.prod
  name     = "pl-prod-codebuild-003-to-admin-target-project"

  service_role = aws_iam_role.target_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type = "NO_SOURCE"
    buildspec = jsonencode({
      version = "0.2"
      phases = {
        build = {
          commands = [
            "echo 'This is the default buildspec that does nothing harmful'",
            "echo 'The attacker will override this with buildspec-override'"
          ]
        }
      }
    })
  }

  # Build batch configuration - required for StartBuildBatch
  build_batch_config {
    service_role = aws_iam_role.target_role.arn
  }

  # Ignore changes since demo scripts may modify the project configuration
  lifecycle {
    ignore_changes = [build_batch_config, source]
  }

  tags = {
    Name        = "pl-prod-codebuild-003-to-admin-target-project"
    Environment = var.environment
    Scenario    = "codebuild-startbuildbatch"
    Purpose     = "vulnerable-project"
  }
}
