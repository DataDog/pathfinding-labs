terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Role that can be assumed by the prod starting user
resource "aws_iam_role" "bucket_access_role" {
  provider = aws.prod
  name     = "pl-bucket-access-role"

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
resource "aws_iam_policy" "bucket_access_role_policy" {
  provider = aws.prod
  name     = "pl-bucket-access-role-policy"

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
resource "aws_iam_role_policy_attachment" "bucket_access_role" {
  provider   = aws.prod
  role       = aws_iam_role.bucket_access_role.name
  policy_arn = aws_iam_policy.bucket_access_role_policy.arn
}

# S3 bucket with sensitive data
resource "aws_s3_bucket" "sensitive_bucket" {
  provider = aws.prod
  bucket   = "pl-sensitive-data-${var.prod_account_id}-${var.resource_suffix}"
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "sensitive_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "sensitive_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "sensitive_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket resource policy that allows the role to access the bucket
resource "aws_s3_bucket_policy" "sensitive_bucket_policy" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBucketAccessRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.bucket_access_role.arn
        }
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.sensitive_bucket.arn,
          "${aws_s3_bucket.sensitive_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Create some sample objects in the bucket
resource "aws_s3_object" "sensitive_file_1" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id
  key      = "sensitive-data-1.txt"
  content  = "This is sensitive data file 1 - contains confidential information"
  etag     = md5("This is sensitive data file 1 - contains confidential information")
}

resource "aws_s3_object" "sensitive_file_2" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id
  key      = "sensitive-data-2.txt"
  content  = "This is sensitive data file 2 - contains PII and financial records"
  etag     = md5("This is sensitive data file 2 - contains PII and financial records")
}

resource "aws_s3_object" "sensitive_file_3" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id
  key      = "admin-credentials.txt"
  content  = "Admin credentials: admin:SuperSecretPassword123!"
  etag     = md5("Admin credentials: admin:SuperSecretPassword123!")
}
