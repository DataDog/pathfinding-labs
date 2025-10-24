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
  name     = "pl-prod-sts-assumerole-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-sts-assumerole-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "sts-assumerole"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Minimal policy for the starting user (just enough to assume the role)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-sts-assumerole-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-one-hop-assumerole-bucket-access-role"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-one-hop-assumerole-bucket-${var.account_id}-${var.resource_suffix}"
}

resource "aws_iam_role" "bucket_access_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-assumerole-bucket-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_user.starting_user.arn }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-one-hop-assumerole-bucket-access-role"
    Environment = var.environment
    Scenario    = "sts-assumerole"
    Purpose     = "bucket-access-role"
  }
}

resource "aws_iam_role_policy" "bucket_access_policy" {
  provider = aws.prod
  name     = "s3-access"
  role     = aws_iam_role.bucket_access_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [aws_s3_bucket.target_bucket.arn, "${aws_s3_bucket.target_bucket.arn}/*"]
      }
    ]
  })
}

resource "aws_s3_object" "sensitive_file" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "🎉 SUCCESS! Simple sts:AssumeRole to bucket access\nFlag: PATHFINDER-ASSUMEROLE-TO-BUCKET-2024"
  etag     = md5("🎉 SUCCESS! Simple sts:AssumeRole to bucket access\nFlag: PATHFINDER-ASSUMEROLE-TO-BUCKET-2024")
}

