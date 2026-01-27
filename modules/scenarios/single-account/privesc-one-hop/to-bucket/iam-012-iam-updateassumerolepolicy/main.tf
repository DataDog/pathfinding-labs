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
  name     = "pl-prod-iam-012-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-iam-012-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "iam-updateassumerolepolicy"
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
  name     = "pl-prod-iam-012-to-bucket-starting-user-policy"
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
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-iam-012-to-bucket-starting-role"
      }
    ]
  })
}

# Target S3 bucket with sensitive data
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-iam-012-to-bucket-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-prod-iam-012-to-bucket-target-bucket"
    Environment = var.environment
    Scenario    = "iam-updateassumerolepolicy"
    Purpose     = "target-bucket"
  }
}

# Target role with S3 bucket access
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-iam-012-to-bucket-target-role"

  # Initially trusts :root (will be modified during attack to trust starting role)
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-iam-012-to-bucket-target-role"
    Environment = var.environment
    Scenario    = "iam-updateassumerolepolicy"
    Purpose     = "target-role"
  }
}

# Policy granting S3 access to the target role
resource "aws_iam_role_policy" "target_role_policy" {
  provider = aws.prod
  name     = "s3-access"
  role     = aws_iam_role.target_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject"]
      Resource = [aws_s3_bucket.target_bucket.arn, "${aws_s3_bucket.target_bucket.arn}/*"]
    }]
  })
}

# Starting role with UpdateAssumeRolePolicy permission on target role
resource "aws_iam_role" "starting_role" {
  provider = aws.prod
  name     = "pl-prod-iam-012-to-bucket-starting-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_user.starting_user.arn }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-iam-012-to-bucket-starting-role"
    Environment = var.environment
    Scenario    = "iam-updateassumerolepolicy"
    Purpose     = "starting-role"
  }
}

# Policy allowing UpdateAssumeRolePolicy on target role and AssumeRole on target role
resource "aws_iam_role_policy" "starting_role_policy" {
  provider = aws.prod
  name     = "update-trust-policy"
  role     = aws_iam_role.starting_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowUpdateAssumeRolePolicy"
        Effect   = "Allow"
        Action   = ["iam:UpdateAssumeRolePolicy", "iam:GetRole"]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid      = "AllowAssumeTargetRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid      = "AllowSelfIdentification"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
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
  content  = "🎉 SUCCESS! You've accessed the S3 bucket via iam:UpdateAssumeRolePolicy privilege escalation.\n\nAttack Path:\n1. User: pl-prod-iam-012-to-bucket-starting-user\n2. Assumed role: pl-prod-iam-012-to-bucket-starting-role\n3. Used iam:UpdateAssumeRolePolicy to modify target role trust policy\n4. Assumed target role: pl-prod-iam-012-to-bucket-target-role\n5. Accessed this S3 bucket\n\nFlag: PATHFINDER-UPDATEASSUMEROLEPOLICY-TO-BUCKET-2024"
  etag     = md5("🎉 SUCCESS! You've accessed the S3 bucket via iam:UpdateAssumeRolePolicy privilege escalation.\n\nAttack Path:\n1. User: pl-prod-iam-012-to-bucket-starting-user\n2. Assumed role: pl-prod-iam-012-to-bucket-starting-role\n3. Used iam:UpdateAssumeRolePolicy to modify target role trust policy\n4. Assumed target role: pl-prod-iam-012-to-bucket-target-role\n5. Accessed this S3 bucket\n\nFlag: PATHFINDER-UPDATEASSUMEROLEPOLICY-TO-BUCKET-2024")
}

