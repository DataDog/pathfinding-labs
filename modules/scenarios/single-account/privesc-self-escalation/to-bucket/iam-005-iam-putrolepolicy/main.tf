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
  name     = "pl-prod-iam-005-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-iam-005-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "iam-putrolepolicy"
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
  name     = "pl-prod-iam-005-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationAssumeStartingRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-iam-005-to-bucket-starting-role"
      }
    ]
  })
}

# Target S3 bucket with sensitive data
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-iam-005-to-bucket-${var.account_id}-${var.resource_suffix}"
}

# Target role with S3 bucket access (will be modified via PutRolePolicy)
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-iam-005-to-bucket-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.starting_role.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-iam-005-to-bucket-target-role"
    Environment = var.environment
    Scenario    = "iam-putrolepolicy"
    Purpose     = "target-role"
  }
}

# Policy granting S3 access to the target role
resource "aws_iam_policy" "bucket_access_policy" {
  provider    = aws.prod
  name        = "pl-prod-iam-005-to-bucket-access-policy"
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

# Attach S3 policy to target role
resource "aws_iam_role_policy_attachment" "bucket_access_attachment" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = aws_iam_policy.bucket_access_policy.arn
}

# Starting role with PutRolePolicy permission on itself
resource "aws_iam_role" "starting_role" {
  provider = aws.prod
  name     = "pl-prod-iam-005-to-bucket-starting-role"

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
    Name        = "pl-prod-iam-005-to-bucket-starting-role"
    Environment = var.environment
    Scenario    = "iam-putrolepolicy"
    Purpose     = "starting-role"
  }
}

# Policy allowing PutRolePolicy on itself to escalate to bucket access
resource "aws_iam_role_policy" "starting_role_policy" {
  provider = aws.prod
  name     = "PutRolePolicyPermission"
  role     = aws_iam_role.starting_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPutRolePolicy"
        Effect = "Allow"
        Action = [
          "iam:PutRolePolicy"
        ]
        Resource = aws_iam_role.starting_role.arn
      },
      {
        Sid    = "RequiredForExploitationAssumeTargetRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = aws_iam_role.target_role.arn
      }
    ]
  })
}

# CTF flag file in the target bucket
resource "aws_s3_object" "flag" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "flag.txt"
  content  = var.flag_value
  etag     = md5(var.flag_value)
}

# Sample sensitive file in the bucket
resource "aws_s3_object" "sensitive_file" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "🎉 SUCCESS! You've accessed the S3 bucket via iam:PutRolePolicy privilege escalation.\n\nAttack Path:\n1. User: pl-prod-iam-005-to-bucket-starting-user\n2. Assumed role: pl-prod-iam-005-to-bucket-starting-role\n3. Used iam:PutRolePolicy to modify self with S3 permissions\n4. Assumed target role: pl-prod-iam-005-to-bucket-target-role\n5. Accessed this S3 bucket\n\nFlag: PATHFINDER-PUTROLEPOLICY-TO-BUCKET-2024"
  etag     = md5("🎉 SUCCESS! You've accessed the S3 bucket via iam:PutRolePolicy privilege escalation.\n\nAttack Path:\n1. User: pl-prod-iam-005-to-bucket-starting-user\n2. Assumed role: pl-prod-iam-005-to-bucket-starting-role\n3. Used iam:PutRolePolicy to modify self with S3 permissions\n4. Assumed target role: pl-prod-iam-005-to-bucket-target-role\n5. Accessed this S3 bucket\n\nFlag: PATHFINDER-PUTROLEPOLICY-TO-BUCKET-2024")
}

