terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# PassRole + SageMaker CreateProcessingJob privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and sagemaker:CreateProcessingJob
# can execute arbitrary code with elevated privileges by creating a SageMaker processing job
# with an admin execution role and a malicious processing script.

# Resource naming convention: pl-prod-sagemaker-003-to-admin-{resource-type}
# sagemaker-003 = pathfinding.cloud ID for PassRole CreateProcessingJob

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-sagemaker-003-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-sagemaker-003-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+sagemaker-createprocessingjob"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# S3 bucket for processing scripts and output
resource "aws_s3_bucket" "processing_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-sagemaker-003-to-admin-bucket-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-prod-sagemaker-003-to-admin-bucket"
    Environment = var.environment
    Scenario    = "iam-passrole+sagemaker-createprocessingjob"
    Purpose     = "processing-scripts"
  }
}

# Block public access to the bucket
resource "aws_s3_bucket_public_access_block" "processing_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.processing_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Policy for the starting user
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-sagemaker-003-to-admin-starting-user-policy"
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
        Resource = aws_iam_role.passable_role.arn
      },
      {
        Sid    = "RequiredForExploitationSageMaker"
        Effect = "Allow"
        Action = [
          "sagemaker:CreateProcessingJob"
        ]
        Resource = "*"
      },
      {
        Sid    = "RequiredForExploitationS3"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.processing_bucket.arn}/*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole",
          "sagemaker:DescribeProcessingJob",
          "s3:ListBucket"
        ]
        Resource = "*"
      }
    ]
  })
}

# Passable admin role (to be passed to SageMaker processing job)
resource "aws_iam_role" "passable_role" {
  provider = aws.prod
  name     = "pl-prod-sagemaker-003-to-admin-passable-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-sagemaker-003-to-admin-passable-role"
    Environment = var.environment
    Scenario    = "iam-passrole+sagemaker-createprocessingjob"
    Purpose     = "passable-admin-role"
  }
}

# Attach AdministratorAccess to the passable role
resource "aws_iam_role_policy_attachment" "passable_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.passable_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/sagemaker-003-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name     = "pl-prod-sagemaker-003-to-admin-flag"
    Scenario = "sagemaker-003-iam-passrole+sagemaker-createprocessingjob"
    Purpose  = "ctf-flag"
  }
}
