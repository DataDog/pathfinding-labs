terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Get the current caller identity for the prod account
data "aws_caller_identity" "prod_terraform_user" {
  provider = aws.prod
}

# Extract role name from the caller identity ARN
locals {
  # Extract role name from ARN like: arn:aws:sts::ACCOUNT:assumed-role/ROLE-NAME/session
  role_name = split("/", split(":", data.aws_caller_identity.prod_terraform_user.arn)[5])[1]
}

# Get the full IAM role details
data "aws_iam_role" "terraform_role" {
  provider = aws.prod
  name     = local.role_name
}

# Role that can be assumed by the prod starting user
resource "aws_iam_role" "exclusive_bucket_access_role" {
  provider = aws.prod
  name     = "pl-exclusive-bucket-access-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.prod_account_id}:user/pl-pathfinder-starting-user-prod"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy that only allows listing all buckets (minimal permission)
resource "aws_iam_policy" "exclusive_bucket_access_role_policy" {
  provider = aws.prod
  name     = "pl-exclusive-bucket-access-role-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach the minimal policy to the role
resource "aws_iam_role_policy_attachment" "exclusive_bucket_access_role" {
  provider = aws.prod
  role     = aws_iam_role.exclusive_bucket_access_role.name
  policy_arn = aws_iam_policy.exclusive_bucket_access_role_policy.arn
}

# S3 bucket with highly sensitive data
resource "aws_s3_bucket" "exclusive_sensitive_bucket" {
  provider = aws.prod
  bucket   = "pl-exclusive-sensitive-data-${var.prod_account_id}-${var.resource_suffix}"
}



# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "exclusive_sensitive_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.exclusive_sensitive_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket resource policy that allows ONLY the specific role and denies everyone else
resource "aws_s3_bucket_policy" "exclusive_sensitive_bucket_policy" {
  provider = aws.prod
  bucket   = aws_s3_bucket.exclusive_sensitive_bucket.id

  depends_on = [
    aws_iam_role.exclusive_bucket_access_role,
    aws_s3_bucket.exclusive_sensitive_bucket
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowExclusiveBucketAccessRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.exclusive_bucket_access_role.arn
        }
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.exclusive_sensitive_bucket.arn,
          "${aws_s3_bucket.exclusive_sensitive_bucket.arn}/*"
        ]
      },
      {
        Sid    = "DenyAllOtherAccess"
        Effect = "Deny"
        Principal = "*"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.exclusive_sensitive_bucket.arn,
          "${aws_s3_bucket.exclusive_sensitive_bucket.arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = [
              aws_iam_role.exclusive_bucket_access_role.arn,
              data.aws_iam_role.terraform_role.arn
            ]
          }
        }
      }
    ]
  })
}

# Create some highly sensitive sample objects in the bucket
resource "aws_s3_object" "exclusive_sensitive_file_1" {
  provider = aws.prod
  bucket   = aws_s3_bucket.exclusive_sensitive_bucket.id
  key      = "top-secret-data-1.txt"
  content  = "TOP SECRET: This file contains classified information about national security operations"
  etag     = md5("TOP SECRET: This file contains classified information about national security operations")
}

resource "aws_s3_object" "exclusive_sensitive_file_2" {
  provider = aws.prod
  bucket   = aws_s3_bucket.exclusive_sensitive_bucket.id
  key      = "confidential-financial-records.txt"
  content  = "CONFIDENTIAL: Financial records including bank account numbers, routing numbers, and transaction history"
  etag     = md5("CONFIDENTIAL: Financial records including bank account numbers, routing numbers, and transaction history")
}

resource "aws_s3_object" "exclusive_sensitive_file_3" {
  provider = aws.prod
  bucket   = aws_s3_bucket.exclusive_sensitive_bucket.id
  key      = "executive-credentials.txt"
  content  = "EXECUTIVE ACCESS: CEO credentials: ceo:UltraSecretPassword456! - DO NOT SHARE"
  etag     = md5("EXECUTIVE ACCESS: CEO credentials: ceo:UltraSecretPassword456! - DO NOT SHARE")
}

resource "aws_s3_object" "exclusive_sensitive_file_4" {
  provider = aws.prod
  bucket   = aws_s3_bucket.exclusive_sensitive_bucket.id
  key      = "legal-documents.txt"
  content  = "LEGAL: Confidential legal documents including contracts, NDAs, and litigation materials"
  etag     = md5("LEGAL: Confidential legal documents including contracts, NDAs, and litigation materials")
}

# Create a test file to verify access restrictions
resource "aws_s3_object" "exclusive_test_file" {
  provider = aws.prod
  bucket   = aws_s3_bucket.exclusive_sensitive_bucket.id
  key      = "access-test.txt"
  content  = "This file is used to test access permissions - should only be accessible by the exclusive role"
  etag     = md5("This file is used to test access permissions - should only be accessible by the exclusive role")
}
