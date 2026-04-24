terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam-deleteaccesskey+createaccesskey privilege escalation scenario (to-bucket)
#
# This scenario demonstrates how a user with iam:DeleteAccessKey and iam:CreateAccessKey
# can bypass the AWS 2-key limit by deleting an existing access key and creating a new one
# for a user with S3 bucket access.

# Resource naming convention: pl-prod-iam-003-to-bucket-{resource-type}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-iam-003-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-iam-003-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "iam-deleteaccesskey+createaccesskey"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (permissions to manipulate target user's access keys)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-003-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationListAccessKeys"
        Effect = "Allow"
        Action = [
          "iam:ListAccessKeys"
        ]
        Resource = aws_iam_user.target_user.arn
      },
      {
        Sid    = "RequiredForExploitationDeleteAccessKey"
        Effect = "Allow"
        Action = [
          "iam:DeleteAccessKey"
        ]
        Resource = aws_iam_user.target_user.arn
      },
      {
        Sid    = "RequiredForExploitationCreateAccessKey"
        Effect = "Allow"
        Action = [
          "iam:CreateAccessKey"
        ]
        Resource = aws_iam_user.target_user.arn
      }
    ]
  })
}

# Target user with S3 bucket access
resource "aws_iam_user" "target_user" {
  provider = aws.prod
  name     = "pl-prod-iam-003-to-bucket-target-user"

  tags = {
    Name        = "pl-prod-iam-003-to-bucket-target-user"
    Environment = var.environment
    Scenario    = "iam-deleteaccesskey+createaccesskey"
    Purpose     = "target-user"
  }
}

# Create TWO access keys for the target user (AWS limit)
# This forces the attacker to delete one before creating a new one
resource "aws_iam_access_key" "target_user_key_1" {
  provider = aws.prod
  user     = aws_iam_user.target_user.name
}

resource "aws_iam_access_key" "target_user_key_2" {
  provider = aws.prod
  user     = aws_iam_user.target_user.name
}

# Policy granting target user S3 bucket access
resource "aws_iam_user_policy" "target_user_policy" {
  provider = aws.prod
  name     = "pl-prod-iam-003-to-bucket-target-user-policy"
  user     = aws_iam_user.target_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.target_bucket.arn,
          "${aws_s3_bucket.target_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Target S3 bucket with sensitive data
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-sensitive-data-iam-003-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-sensitive-data-iam-003-bucket"
    Environment = var.environment
    Scenario    = "iam-deleteaccesskey+createaccesskey"
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
  content  = "This is sensitive data that should only be accessible to authorized principals. Scenario: iam-deleteaccesskey+createaccesskey"
}

# CTF flag stored as an S3 object in the target bucket. The attacker retrieves this after
# successfully deleting an existing access key and creating a new one for the target user,
# then using those credentials to read from the target bucket.
resource "aws_s3_object" "flag" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "flag.txt"
  content  = var.flag_value
}
