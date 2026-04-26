terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Target S3 bucket
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-iam-002-to-bucket-${var.account_id}-${var.resource_suffix}"
}

# Privileged user with S3 access
resource "aws_iam_user" "bucket_access_user" {
  provider = aws.prod
  name     = "pl-prod-iam-002-to-bucket-access-user"
}

# Policy granting S3 access
resource "aws_iam_user_policy" "bucket_access_policy" {
  provider = aws.prod
  name     = "pl-bucket-access-policy"
  user     = aws_iam_user.bucket_access_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.target_bucket.arn,
          "${aws_s3_bucket.target_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Starting user with CreateAccessKey permission
resource "aws_iam_user" "privesc_user" {
  provider = aws.prod
  name     = "pl-prod-iam-002-to-bucket-privesc-user"
}

# Create access keys for the starting user
resource "aws_iam_access_key" "privesc_user_key" {
  provider = aws.prod
  user     = aws_iam_user.privesc_user.name
}

# Policy allowing CreateAccessKey on the bucket access user
resource "aws_iam_user_policy" "privesc_policy" {
  provider = aws.prod
  name     = "pl-createaccesskey-privesc-policy"
  user     = aws_iam_user.privesc_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationCreateAccessKey"
        Effect = "Allow"
        Action = [
          "iam:CreateAccessKey"
        ]
        Resource = aws_iam_user.bucket_access_user.arn
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "iam:ListUsers",
          "iam:GetUserPolicy",
          "iam:ListAttachedUserPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# Sample sensitive file
resource "aws_s3_object" "sensitive_file" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "🎉 SUCCESS! You've accessed the S3 bucket via iam:CreateAccessKey privilege escalation.\n\nFlag: PATHFINDER-CREATEACCESSKEY-TO-BUCKET-2024"
  etag     = md5("🎉 SUCCESS! You've accessed the S3 bucket via iam:CreateAccessKey privilege escalation.\n\nFlag: PATHFINDER-CREATEACCESSKEY-TO-BUCKET-2024")
}

# CTF flag stored as an S3 object in the target bucket. The attacker retrieves this after
# successfully creating access keys for the bucket access user and using those credentials
# to read from the target bucket. Readable by any principal with s3:GetObject on this bucket.
resource "aws_s3_object" "flag" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "flag.txt"
  content  = var.flag_value
}

