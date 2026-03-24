terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod, aws.attacker]
    }
  }
}

# Data Pipeline privilege escalation scenario (to-bucket with resource policy bypass)
#
# This scenario demonstrates how a user with datapipeline permissions and iam:PassRole
# can create a pipeline that exfiltrates S3 data by leveraging an overly permissive
# bucket resource policy that allows any principal to write objects.

# Resource naming convention: pl-prod-datapipeline-001-to-bucket-{resource-type}
# All resources use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-datapipeline-001-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-datapipeline-001-to-bucket-starting-user"
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

# Pipeline role - trusted by DataPipeline service, has read-only S3 access
resource "aws_iam_role" "pipeline_role" {
  provider = aws.prod
  name     = "pl-prod-datapipeline-001-to-bucket-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "datapipeline.amazonaws.com",
            "elasticmapreduce.amazonaws.com",
            "ec2.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-datapipeline-001-to-bucket-pipeline-role"
    Environment = var.environment
    Scenario    = "iam-passrole+datapipeline-pipeline"
    Purpose     = "pipeline-role"
  }
}

# Pipeline role policy - ONLY read access to sensitive bucket (appears safe)
resource "aws_iam_role_policy" "pipeline_role_policy" {
  provider = aws.prod
  name     = "pl-prod-datapipeline-001-to-bucket-pipeline-policy"
  role     = aws_iam_role.pipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.sensitive_bucket.arn,
          "${aws_s3_bucket.sensitive_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:RunInstances",
          "ec2:TerminateInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# Sensitive bucket containing target data
resource "aws_s3_bucket" "sensitive_bucket" {
  provider = aws.prod
  bucket   = "pl-sensitive-data-datapipeline-001-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-sensitive-data-datapipeline-001"
    Environment = var.environment
    Scenario    = "iam-passrole+datapipeline-pipeline"
    Purpose     = "target-bucket"
  }
}

# Block public access on sensitive bucket
resource "aws_s3_bucket_public_access_block" "sensitive_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sensitive data to the target bucket
resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id
  key      = "secret-data.txt"
  content  = "CONFIDENTIAL: Database credentials and API keys for production systems."
}

# Exfiltration bucket with overly permissive resource policy
resource "aws_s3_bucket" "exfil_bucket" {
  provider = aws.prod
  bucket   = "pl-exfil-bucket-datapipeline-001-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-exfil-bucket-datapipeline-001"
    Environment = var.environment
    Scenario    = "iam-passrole+datapipeline-pipeline"
    Purpose     = "exfil-bucket"
  }
}

# Block public access on exfil bucket (but resource policy still allows access)
resource "aws_s3_bucket_public_access_block" "exfil_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.exfil_bucket.id

  block_public_acls       = true
  block_public_policy     = false # Must be false to allow resource policy
  ignore_public_acls      = true
  restrict_public_buckets = false # Must be false to allow resource policy
}

# CRITICAL: Overly permissive bucket policy allowing any principal to write
resource "aws_s3_bucket_policy" "exfil_bucket_policy" {
  provider = aws.prod
  bucket   = aws_s3_bucket.exfil_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowDataPipelineWrite"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.exfil_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = var.account_id
          }
        }
      }
    ]
  })
}

# Starting user policy - datapipeline permissions, PassRole, and read access to exfil bucket
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-datapipeline-001-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.pipeline_role.arn
      },
      {
        Sid    = "RequiredForExploitationReadExfilBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.exfil_bucket.arn,
          "${aws_s3_bucket.exfil_bucket.arn}/*"
        ]
      }
    ]
  })
}
