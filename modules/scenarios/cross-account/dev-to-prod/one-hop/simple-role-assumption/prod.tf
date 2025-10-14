# S3 bucket in prod account
resource "aws_s3_bucket" "sensitive_data" {
  provider = aws.prod
  bucket   = "pl-x-account-sensitive-data-${var.prod_account_id}-${var.resource_suffix}"
}

# Enable versioning for the bucket
resource "aws_s3_bucket_versioning" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_data.id
  versioning_configuration {
    status = "Disabled"
  }
}

# IAM role in prod account that can access the S3 bucket
resource "aws_iam_role" "s3_access_role" {
  provider = aws.prod
  name     = "pl-x-account-prod-s3-sensitive-data-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${var.dev_account_id}:role/${aws_iam_role.s3_access_role_dev.name}",
            "arn:aws:iam::${var.dev_account_id}:user/${aws_iam_user.s3_access_user.name}"
          ]
        }
      }
    ]
  })
}

# IAM policy for the role to access the S3 bucket
resource "aws_iam_role_policy" "s3_access_policy" {
  provider = aws.prod
  name     = "pl-x-account-prod-s3-sensitive-data-access-policy"
  role     = aws_iam_role.s3_access_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.sensitive_data.arn,
          "${aws_s3_bucket.sensitive_data.arn}/*"
        ]
      }
    ]
  })
} 