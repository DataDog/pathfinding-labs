terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# Test Reverse Blast Radius - Direct and Indirect to Bucket
#
# This tool testing scenario creates two distinct paths to access an S3 bucket:
# Path 1 (Direct): user1 → (direct S3 permissions) → bucket
# Path 2 (Indirect): user2 → (sts:AssumeRole) → role3 → (S3 permissions) → bucket
#
# Purpose: Validate that security tools can detect both direct and indirect access paths
# when performing reverse blast radius analysis (who can access this bucket?)

# Resource naming convention: pl-prod-rbr-di-{resource-type}
# Use provider = aws.prod for all resources

# =============================================================================
# TARGET S3 BUCKET
# =============================================================================

# Target S3 bucket with sensitive data
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-sensitive-data-rbr-di-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-sensitive-data-rbr-di-bucket"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-direct-and-indirect-to-bucket"
    Purpose     = "target-bucket"
  }
}

# Block public access (this is a private bucket)
resource "aws_s3_bucket_public_access_block" "target_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload a test file to demonstrate access
resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is sensitive data that should only be accessible to authorized principals. If you can read this via direct access (user1) or indirect access through role assumption (user2 → role3), the test demonstrates both access paths successfully!"
}

# =============================================================================
# PATH 1: DIRECT ACCESS (USER1 → BUCKET)
# =============================================================================

# User1 with direct S3 access to the bucket
resource "aws_iam_user" "user1" {
  provider = aws.prod
  name     = "pl-prod-rbr-di-user1"

  tags = {
    Name        = "pl-prod-rbr-di-user1"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-direct-and-indirect-to-bucket"
    Purpose     = "direct-access-user"
  }
}

# Create access keys for user1
resource "aws_iam_access_key" "user1_key" {
  provider = aws.prod
  user     = aws_iam_user.user1.name
}

# Policy granting user1 direct S3 access
resource "aws_iam_user_policy" "user1_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-di-user1-policy"
  user     = aws_iam_user.user1.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListAllBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      },
      {
        Sid    = "DirectBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.target_bucket.arn,
          "${aws_s3_bucket.target_bucket.arn}/*"
        ]
      },
      {
        Sid    = "GetCallerIdentity"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# PATH 2: INDIRECT ACCESS (USER2 → ROLE3 → BUCKET)
# =============================================================================

# User2 with ability to assume role3
resource "aws_iam_user" "user2" {
  provider = aws.prod
  name     = "pl-prod-rbr-di-user2"

  tags = {
    Name        = "pl-prod-rbr-di-user2"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-direct-and-indirect-to-bucket"
    Purpose     = "indirect-access-user"
  }
}

# Create access keys for user2
resource "aws_iam_access_key" "user2_key" {
  provider = aws.prod
  user     = aws_iam_user.user2.name
}

# Policy granting user2 ability to assume role3
resource "aws_iam_user_policy" "user2_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-di-user2-policy"
  user     = aws_iam_user.user2.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeRole3"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = aws_iam_role.role3.arn
      },
      {
        Sid    = "GetCallerIdentity"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Role3 with S3 access (trust policy allows user2 to assume it)
resource "aws_iam_role" "role3" {
  provider = aws.prod
  name     = "pl-prod-rbr-di-role3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = aws_iam_user.user2.arn
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-rbr-di-role3"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-direct-and-indirect-to-bucket"
    Purpose     = "indirect-access-role"
  }
}

# Policy granting role3 S3 access (same permissions as user1)
resource "aws_iam_role_policy" "role3_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-di-role3-policy"
  role     = aws_iam_role.role3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListAllBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      },
      {
        Sid    = "IndirectBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.target_bucket.arn,
          "${aws_s3_bucket.target_bucket.arn}/*"
        ]
      },
      {
        Sid    = "GetCallerIdentity"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}
