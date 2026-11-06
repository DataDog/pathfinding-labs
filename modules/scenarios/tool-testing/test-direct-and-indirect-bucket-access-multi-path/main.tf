terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Test Direct and Indirect Bucket Access via Multiple Reachability Paths
#
# This tool testing scenario creates THREE independent starting principals that all
# reach the same S3 bucket through three different mechanisms:
#
# Path 1 (Direct):                    user-direct      → (direct S3 permissions)              → bucket
# Path 2 (Indirect via AssumeRole):   user-assumer      → sts:AssumeRole                        → role-trusted (already trusts user-assumer, has S3 perms) → bucket
# Path 3 (Indirect via trust bypass): user-trustbypass  → iam:UpdateAssumeRolePolicy + AssumeRole → role-untrusted (initially only trusts ec2.amazonaws.com, has S3 perms) → bucket
#
# Purpose: Validate that graph/CSPM tools surface ALL reachable principals for a target
# bucket at once, not just the ones with a direct policy grant.
#
# Resource naming convention: pl-prod-dimp-{resource-type}
# Use provider = aws.prod for all resources

# =============================================================================
# TARGET S3 BUCKET
# =============================================================================

resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-dimp-bucket-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-dimp-bucket"
    Environment = var.environment
    Scenario    = "test-direct-and-indirect-bucket-access-multi-path"
    Purpose     = "target-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "target_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is sensitive data that should only be accessible to authorized principals. If you can read this via direct access (pl-prod-dimp-user-direct), indirect access through an already-trusted role (pl-prod-dimp-user-assumer -> pl-prod-dimp-role-trusted), or indirect access through a trust-policy bypass (pl-prod-dimp-user-trustbypass -> pl-prod-dimp-role-untrusted), the test demonstrates all three access paths successfully!"
}

# =============================================================================
# PATH 1: DIRECT ACCESS (USER-DIRECT -> BUCKET)
# =============================================================================

resource "aws_iam_user" "user_direct" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-dimp-user-direct"

  tags = {
    Name        = "pl-prod-dimp-user-direct"
    Environment = var.environment
    Scenario    = "test-direct-and-indirect-bucket-access-multi-path"
    Purpose     = "direct-access-user"
  }
}

resource "aws_iam_access_key" "user_direct" {
  provider = aws.prod
  user     = aws_iam_user.user_direct.name
}

resource "aws_iam_user_policy" "user_direct" {
  provider = aws.prod
  name     = "pl-prod-dimp-user-direct-policy"
  user     = aws_iam_user.user_direct.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
      {
        Sid    = "RequiredForExploitationDirectBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid    = "RequiredForExploitationDirectBucketList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = aws_s3_bucket.target_bucket.arn
      },
    ]
  })
}

# =============================================================================
# PATH 2: INDIRECT ACCESS VIA STS:ASSUMEROLE (USER-ASSUMER -> ROLE-TRUSTED -> BUCKET)
# =============================================================================

resource "aws_iam_user" "user_assumer" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-dimp-user-assumer"

  tags = {
    Name        = "pl-prod-dimp-user-assumer"
    Environment = var.environment
    Scenario    = "test-direct-and-indirect-bucket-access-multi-path"
    Purpose     = "indirect-access-user-assumer"
  }
}

resource "aws_iam_access_key" "user_assumer" {
  provider = aws.prod
  user     = aws_iam_user.user_assumer.name
}

resource "aws_iam_user_policy" "user_assumer" {
  provider = aws.prod
  name     = "pl-prod-dimp-user-assumer-policy"
  user     = aws_iam_user.user_assumer.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
      {
        Sid      = "RequiredForExploitationAssumeRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.role_trusted.arn
      },
    ]
  })
}

# Role that already trusts user-assumer directly (classic, already-correct trust relationship)
resource "aws_iam_role" "role_trusted" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-dimp-role-trusted"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = aws_iam_user.user_assumer.arn
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-dimp-role-trusted"
    Environment = var.environment
    Scenario    = "test-direct-and-indirect-bucket-access-multi-path"
    Purpose     = "indirect-access-role-trusted"
  }
}

resource "aws_iam_role_policy" "role_trusted" {
  provider = aws.prod
  name     = "pl-prod-dimp-role-trusted-policy"
  role     = aws_iam_role.role_trusted.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationIndirectBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid    = "RequiredForExploitationIndirectBucketList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = aws_s3_bucket.target_bucket.arn
      },
    ]
  })
}

# =============================================================================
# PATH 3: INDIRECT ACCESS VIA IAM:UPDATEASSUMEROLEPOLICY TRUST-POLICY BYPASS
# (USER-TRUSTBYPASS -> ROLE-UNTRUSTED -> BUCKET)
# =============================================================================

resource "aws_iam_user" "user_trustbypass" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-dimp-user-trustbypass"

  tags = {
    Name        = "pl-prod-dimp-user-trustbypass"
    Environment = var.environment
    Scenario    = "test-direct-and-indirect-bucket-access-multi-path"
    Purpose     = "indirect-access-user-trustbypass"
  }
}

resource "aws_iam_access_key" "user_trustbypass" {
  provider = aws.prod
  user     = aws_iam_user.user_trustbypass.name
}

resource "aws_iam_user_policy" "user_trustbypass" {
  provider = aws.prod
  name     = "pl-prod-dimp-user-trustbypass-policy"
  user     = aws_iam_user.user_trustbypass.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
      {
        Sid      = "RequiredForExploitationUpdateAssumeRolePolicy"
        Effect   = "Allow"
        Action   = ["iam:UpdateAssumeRolePolicy"]
        Resource = aws_iam_role.role_untrusted.arn
      },
      {
        Sid      = "RequiredForExploitationAssumeRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.role_untrusted.arn
      },
    ]
  })
}

# Role that initially trusts only ec2.amazonaws.com (NOT user-trustbypass). The user must
# call iam:UpdateAssumeRolePolicy to add itself before it can assume this role.
resource "aws_iam_role" "role_untrusted" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-dimp-role-untrusted"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-dimp-role-untrusted"
    Environment = var.environment
    Scenario    = "test-direct-and-indirect-bucket-access-multi-path"
    Purpose     = "indirect-access-role-untrusted"
  }
}

resource "aws_iam_role_policy" "role_untrusted" {
  provider = aws.prod
  name     = "pl-prod-dimp-role-untrusted-policy"
  role     = aws_iam_role.role_untrusted.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationIndirectBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid    = "RequiredForExploitationIndirectBucketList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = aws_s3_bucket.target_bucket.arn
      },
    ]
  })
}
