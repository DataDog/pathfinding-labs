# IAM UpdateLoginProfile privilege escalation to S3 bucket access scenario
#
# This scenario demonstrates how a user with iam:UpdateLoginProfile permission
# can escalate privileges by changing the console password of an existing user
# who has S3 bucket access and an existing login profile.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Resource naming convention: pl-prod-iam-006-to-bucket-*
# iam-006 = pathfinding.cloud ID for iam:UpdateLoginProfile privilege escalation

# Target S3 bucket with sensitive data
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-iam-006-to-bucket-sensitive-data-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-prod-iam-006-to-bucket-sensitive-data"
    Environment = var.environment
    Scenario    = "iam-006-iam-updateloginprofile-bucket"
    Purpose     = "sensitive-data"
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
  content  = "SUCCESS! You've accessed the S3 bucket via iam:UpdateLoginProfile privilege escalation.\n\nFlag: PATHFINDER-UPDATELOGINPROFILE-TO-BUCKET-2025\n\nThis demonstrates how updating login profiles can lead to sensitive data access."
  etag     = md5("SUCCESS! You've accessed the S3 bucket via iam:UpdateLoginProfile privilege escalation.\n\nFlag: PATHFINDER-UPDATELOGINPROFILE-TO-BUCKET-2025\n\nThis demonstrates how updating login profiles can lead to sensitive data access.")
}

# Target user with S3 bucket access and an existing login profile
# This user has console access and can read from the sensitive bucket
resource "aws_iam_user" "target_user" {
  provider = aws.prod
  name     = "pl-prod-iam-006-to-bucket-user"

  tags = {
    Name        = "pl-prod-iam-006-to-bucket-user"
    Environment = var.environment
    Scenario    = "iam-006-iam-updateloginprofile-bucket"
    Purpose     = "target-user"
  }
}

# Create an existing login profile for the target user
# This represents a pre-existing console password that the attacker will update
resource "aws_iam_user_login_profile" "target_login_profile" {
  provider                = aws.prod
  user                    = aws_iam_user.target_user.name
  password_reset_required = false
}

# Policy that grants S3 bucket access to the target user
resource "aws_iam_user_policy" "target_user_s3_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-006-to-bucket-target-policy"
  user     = aws_iam_user.target_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.target_bucket.arn,
          "${aws_s3_bucket.target_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Starting user that can update login profiles (privilege escalation vector)
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-iam-006-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-iam-006-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "iam-006-iam-updateloginprofile-bucket"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy that allows the starting user to update the target user's login profile
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-006-to-bucket-starting-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationUpdateLoginProfile"
        Effect = "Allow"
        Action = [
          "iam:UpdateLoginProfile"
        ]
        Resource = aws_iam_user.target_user.arn
      }
    ]
  })
}
