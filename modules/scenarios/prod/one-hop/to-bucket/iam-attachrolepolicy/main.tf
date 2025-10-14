terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Target S3 bucket with sensitive data
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-one-hop-attachrolepolicy-bucket-${var.account_id}-${var.resource_suffix}"
}

# Privileged role that has S3 access
resource "aws_iam_role" "bucket_access_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-attachrolepolicy-bucket-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:user/pl-pathfinder-starting-user-prod"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy granting S3 access
resource "aws_iam_policy" "bucket_access_policy" {
  provider = aws.prod
  name     = "pl-prod-one-hop-attachrolepolicy-bucket-access-policy"
  description = "Grants read/write access to the target S3 bucket"

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

# Attach S3 policy to privileged role
resource "aws_iam_role_policy_attachment" "bucket_access_attachment" {
  provider   = aws.prod
  role       = aws_iam_role.bucket_access_role.name
  policy_arn = aws_iam_policy.bucket_access_policy.arn
}

# Starting role with AttachRolePolicy permission
resource "aws_iam_role" "privesc_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-attachrolepolicy-bucket-privesc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:user/pl-pathfinder-starting-user-prod"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy allowing AttachRolePolicy on the bucket access role
resource "aws_iam_policy" "privesc_policy" {
  provider = aws.prod
  name     = "pl-prod-one-hop-attachrolepolicy-bucket-privesc-policy"
  description = "Allows attaching policies to the bucket access role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy"
        ]
        Resource = aws_iam_role.bucket_access_role.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = aws_iam_role.bucket_access_role.arn
      }
    ]
  })
}

# Attach privilege escalation policy to starting role
resource "aws_iam_role_policy_attachment" "privesc_policy_attachment" {
  provider = aws.prod
  role       = aws_iam_role.privesc_role.name
  policy_arn = aws_iam_policy.privesc_policy.arn
}

# Sample sensitive file in the bucket
resource "aws_s3_object" "sensitive_file" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "🎉 SUCCESS! You've accessed the S3 bucket via iam:AttachRolePolicy privilege escalation.\n\nAttack Path:\n1. Assumed pl-prod-one-hop-attachrolepolicy-bucket-privesc-role\n2. Used iam:AttachRolePolicy to attach an admin or S3 policy to bucket-access-role\n3. Assumed the bucket access role\n4. Accessed this S3 bucket\n\nFlag: PATHFINDER-ATTACHROLEPOLICY-TO-BUCKET-2024"
  etag     = md5("🎉 SUCCESS! You've accessed the S3 bucket via iam:AttachRolePolicy privilege escalation.\n\nAttack Path:\n1. Assumed pl-prod-one-hop-attachrolepolicy-bucket-privesc-role\n2. Used iam:AttachRolePolicy to attach an admin or S3 policy to bucket-access-role\n3. Assumed the bucket access role\n4. Accessed this S3 bucket\n\nFlag: PATHFINDER-ATTACHROLEPOLICY-TO-BUCKET-2024")
}

