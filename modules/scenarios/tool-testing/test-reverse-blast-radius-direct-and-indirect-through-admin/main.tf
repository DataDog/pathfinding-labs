terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# Test Reverse Blast Radius: Direct and Indirect Through Admin
#
# This scenario demonstrates reverse blast radius detection by creating two paths to the same S3 bucket:
# 1. Direct access: user1 has explicit S3 permissions to access the bucket
# 2. Indirect access: user2 can assume an admin role, which grants access to everything including the bucket
#
# Security tools should detect that BOTH users can access the bucket:
# - user1 via direct S3 permissions
# - user2 via administrative permissions (indirect path)
#
# This tests whether security tools can properly calculate reverse blast radius and identify
# all principals that can access a specific resource, including those with indirect access
# through administrative roles.

# Resource naming convention: pl-prod-rbr-admin-{resource-type}

# =============================================================================
# USER 1: Direct S3 Access
# =============================================================================

# User with direct S3 access to the target bucket
resource "aws_iam_user" "user1" {
  provider = aws.prod
  name     = "pl-prod-rbr-admin-user1"

  tags = {
    Name        = "pl-prod-rbr-admin-user1"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-direct-and-indirect-through-admin"
    Purpose     = "direct-s3-access-user"
  }
}

# Create access keys for user1
resource "aws_iam_access_key" "user1_key" {
  provider = aws.prod
  user     = aws_iam_user.user1.name
}

# User1 policy: Direct S3 permissions to the target bucket
resource "aws_iam_user_policy" "user1_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-admin-user1-policy"
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
# USER 2: Indirect Access Through Admin Role
# =============================================================================

# User with ability to assume the admin role
resource "aws_iam_user" "user2" {
  provider = aws.prod
  name     = "pl-prod-rbr-admin-user2"

  tags = {
    Name        = "pl-prod-rbr-admin-user2"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-direct-and-indirect-through-admin"
    Purpose     = "indirect-access-via-admin-user"
  }
}

# Create access keys for user2
resource "aws_iam_access_key" "user2_key" {
  provider = aws.prod
  user     = aws_iam_user.user2.name
}

# User2 policy: Only permission to assume the admin role
resource "aws_iam_user_policy" "user2_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-admin-user2-policy"
  user     = aws_iam_user.user2.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeAdminRole"
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

# =============================================================================
# ROLE 3: Admin Role (Provides Indirect Access)
# =============================================================================

# Admin role that user2 can assume
resource "aws_iam_role" "role3" {
  provider = aws.prod
  name     = "pl-prod-rbr-admin-role3"

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
    Name        = "pl-prod-rbr-admin-role3"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-direct-and-indirect-through-admin"
    Purpose     = "admin-role"
  }
}

# Attach AdministratorAccess to role3 (grants access to everything including S3)
resource "aws_iam_role_policy_attachment" "role3_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.role3.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# =============================================================================
# TARGET S3 BUCKET
# =============================================================================

# Target S3 bucket with sensitive data
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-sensitive-data-rbr-admin-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-sensitive-data-rbr-admin-bucket"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-direct-and-indirect-through-admin"
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
  content  = "This is sensitive data that should only be accessible to authorized principals. If you can read this via direct access (user1) or indirect access through an admin role (user2 → role3), the test demonstrates that security tools should detect both direct permissions and administrative access paths!"
}
