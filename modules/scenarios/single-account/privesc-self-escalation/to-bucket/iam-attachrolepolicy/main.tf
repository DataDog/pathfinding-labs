terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-arp-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-arp-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "iam-attachrolepolicy"
    Purpose     = "starting-user"
  }
}

# Access key for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Basic policy for starting user
resource "aws_iam_user_policy" "starting_user_basic" {
  provider = aws.prod
  name     = "pl-prod-arp-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:GetUser"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-arp-to-bucket-starting-role"
      }
    ]
  })
}

# Target S3 bucket with sensitive data
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-arp-to-bucket-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-prod-arp-to-bucket-target-bucket"
    Environment = var.environment
    Scenario    = "iam-attachrolepolicy"
    Purpose     = "target-bucket"
  }
}

# Policy granting S3 access that can be attached during escalation
resource "aws_iam_policy" "bucket_access_policy" {
  provider    = aws.prod
  name        = "pl-prod-arp-to-bucket-access-policy"
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

  tags = {
    Name        = "pl-prod-arp-to-bucket-access-policy"
    Environment = var.environment
    Scenario    = "iam-attachrolepolicy"
    Purpose     = "bucket-access-policy"
  }
}

# Starting role with AttachRolePolicy permission on itself
resource "aws_iam_role" "starting_role" {
  provider = aws.prod
  name     = "pl-prod-arp-to-bucket-starting-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.starting_user.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-arp-to-bucket-starting-role"
    Environment = var.environment
    Scenario    = "iam-attachrolepolicy"
    Purpose     = "starting-role"
  }
}

# Policy allowing AttachRolePolicy on itself (self-escalation)
resource "aws_iam_role_policy" "starting_role_policy" {
  provider = aws.prod
  name     = "AttachRolePolicyPermission"
  role     = aws_iam_role.starting_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAttachRolePolicyOnSelf"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:GetRole",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = aws_iam_role.starting_role.arn
      },
      {
        Sid    = "AllowSelfIdentification"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Sample sensitive file in the bucket
resource "aws_s3_object" "sensitive_file" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "🎉 SUCCESS! You've accessed the S3 bucket via iam:AttachRolePolicy privilege escalation.\n\nAttack Path:\n1. User: pl-prod-arp-to-bucket-starting-user\n2. Assumed role: pl-prod-arp-to-bucket-starting-role\n3. Used iam:AttachRolePolicy to attach S3 policy to self\n4. Accessed this S3 bucket\n\nFlag: PATHFINDER-ATTACHROLEPOLICY-TO-BUCKET-2024"
  etag     = md5("🎉 SUCCESS! You've accessed the S3 bucket via iam:AttachRolePolicy privilege escalation.\n\nAttack Path:\n1. User: pl-prod-arp-to-bucket-starting-user\n2. Assumed role: pl-prod-arp-to-bucket-starting-role\n3. Used iam:AttachRolePolicy to attach S3 policy to self\n4. Accessed this S3 bucket\n\nFlag: PATHFINDER-ATTACHROLEPOLICY-TO-BUCKET-2024")
}

