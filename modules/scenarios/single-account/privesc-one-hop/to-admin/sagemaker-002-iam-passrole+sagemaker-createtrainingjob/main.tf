terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# PassRole + SageMaker CreateTrainingJob privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and sagemaker:CreateTrainingJob
# can create a training job with a malicious script that executes with an admin role's privileges.

# Resource naming convention: pl-prod-sagemaker-002-to-admin-{resource-type}
# sagemaker-002 = Pathfinding.cloud ID for PassRole + CreateTrainingJob

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-sagemaker-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-sagemaker-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+sagemaker-createtrainingjob"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (PassRole, CreateTrainingJob, S3 access)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-sagemaker-002-to-admin-starting-user-policy"
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
        Resource = aws_iam_role.passable_admin_role.arn
      },
      {
        Sid    = "requiredPermissions2"
        Effect = "Allow"
        Action = [
          "sagemaker:CreateTrainingJob"
        ]
        Resource = "*"
      },
      {
        Sid    = "requiredPermissions3"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.training_bucket.arn}/*"
      },
      {
        Sid    = "helpfulAdditionalPermissions1"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions2"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions3"
        Effect = "Allow"
        Action = [
          "sagemaker:DescribeTrainingJob"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions4"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.training_bucket.arn
      }
    ]
  })
}

# Passable admin role that trusts SageMaker
resource "aws_iam_role" "passable_admin_role" {
  provider = aws.prod
  name     = "pl-prod-sagemaker-002-to-admin-passable-role"

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
    Name        = "pl-prod-sagemaker-002-to-admin-passable-role"
    Environment = var.environment
    Scenario    = "iam-passrole+sagemaker-createtrainingjob"
    Purpose     = "passable-admin-role"
  }
}

# Attach AdministratorAccess to the passable role
resource "aws_iam_role_policy_attachment" "passable_admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.passable_admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# S3 bucket for training scripts and output
resource "aws_s3_bucket" "training_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-sagemaker-002-to-admin-bucket-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-prod-sagemaker-002-to-admin-bucket"
    Environment = var.environment
    Scenario    = "iam-passrole+sagemaker-createtrainingjob"
    Purpose     = "training-bucket"
  }
}

# Block public access to the training bucket
resource "aws_s3_bucket_public_access_block" "training_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.training_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
