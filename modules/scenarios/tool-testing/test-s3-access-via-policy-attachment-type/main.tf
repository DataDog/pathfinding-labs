terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# =============================================================================
# Tool Testing: S3 Access via Inline and Managed Policy Attachment Types
# =============================================================================
#
# This scenario creates 4 independent test principals (2 IAM users, 2 IAM
# roles) that each already have full read/write access to the same S3
# bucket, granted via two different IAM attachment mechanisms:
#   - Inline policy embedded directly on the principal
#   - Customer-managed policy attached to the principal
#
# The point of the scenario is NOT bucket misconfiguration - the bucket is a
# plain private bucket. The point is to validate that a graph/CSPM tool
# infers identical bucket-access edges for all 4 principals regardless of
# the underlying IAM attachment mechanism used to grant that access.
#
# Resource naming convention: pl-prod-patn-{principal-type}-{attachment-type}

# =============================================================================
# TARGET S3 BUCKET
# =============================================================================

resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-patn-bucket-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-patn-bucket-${var.account_id}-${var.resource_suffix}"
    Environment = var.environment
    Scenario    = "test-s3-access-via-policy-attachment-type"
    Purpose     = "target-bucket"
  }
}

# =============================================================================
# STARTING USER
# =============================================================================
#
# The starting user's only job is to sts:AssumeRole into the two role-based
# test principals. It has no direct S3 access of its own.

resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-patn-starting-user"

  tags = {
    Name        = "pl-prod-patn-starting-user"
    Environment = var.environment
    Scenario    = "test-s3-access-via-policy-attachment-type"
    Purpose     = "starting-user-for-role-assumption"
  }
}

resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

resource "aws_iam_user_policy" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-patn-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Sid    = "RequiredForExploitationAssumeRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          aws_iam_role.role_inline.arn,
          aws_iam_role.role_managed.arn
        ]
      }
    ]
  })
}

# =============================================================================
# CUSTOMER MANAGED S3 ACCESS POLICY
# =============================================================================
#
# Shared by both the managed-policy user and the managed-policy role to
# demonstrate the same access mechanism across principal types.

resource "aws_iam_policy" "s3_access_managed_policy" {
  provider = aws.prod
  name     = "pl-prod-patn-s3-access-managed-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid      = "RequiredForExploitationListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.target_bucket.arn
      },
      {
        Sid      = "RequiredForExploitationListAllMyBuckets"
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-patn-s3-access-managed-policy"
    Environment = var.environment
    Scenario    = "test-s3-access-via-policy-attachment-type"
  }
}

# =============================================================================
# IAM USER - INLINE POLICY
# =============================================================================

resource "aws_iam_user" "user_inline" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-patn-user-inline"

  tags = {
    Name        = "pl-prod-patn-user-inline"
    Environment = var.environment
    Scenario    = "test-s3-access-via-policy-attachment-type"
    Purpose     = "test-principal-user-inline-policy"
  }
}

resource "aws_iam_access_key" "user_inline" {
  provider = aws.prod
  user     = aws_iam_user.user_inline.name
}

resource "aws_iam_user_policy" "user_inline" {
  provider = aws.prod
  name     = "pl-prod-patn-user-inline-policy"
  user     = aws_iam_user.user_inline.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid      = "RequiredForExploitationListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.target_bucket.arn
      },
      {
        Sid      = "RequiredForExploitationListAllMyBuckets"
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# IAM USER - MANAGED POLICY
# =============================================================================

resource "aws_iam_user" "user_managed" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-patn-user-managed"

  tags = {
    Name        = "pl-prod-patn-user-managed"
    Environment = var.environment
    Scenario    = "test-s3-access-via-policy-attachment-type"
    Purpose     = "test-principal-user-managed-policy"
  }
}

resource "aws_iam_access_key" "user_managed" {
  provider = aws.prod
  user     = aws_iam_user.user_managed.name
}

resource "aws_iam_user_policy_attachment" "user_managed" {
  provider   = aws.prod
  user       = aws_iam_user.user_managed.name
  policy_arn = aws_iam_policy.s3_access_managed_policy.arn
}

# =============================================================================
# IAM ROLE - INLINE POLICY
# =============================================================================

resource "aws_iam_role" "role_inline" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-patn-role-inline"

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
    Name        = "pl-prod-patn-role-inline"
    Environment = var.environment
    Scenario    = "test-s3-access-via-policy-attachment-type"
    Purpose     = "test-principal-role-inline-policy"
  }
}

resource "aws_iam_role_policy" "role_inline" {
  provider = aws.prod
  name     = "pl-prod-patn-role-inline-policy"
  role     = aws_iam_role.role_inline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid      = "RequiredForExploitationListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.target_bucket.arn
      },
      {
        Sid      = "RequiredForExploitationListAllMyBuckets"
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# IAM ROLE - MANAGED POLICY
# =============================================================================

resource "aws_iam_role" "role_managed" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-patn-role-managed"

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
    Name        = "pl-prod-patn-role-managed"
    Environment = var.environment
    Scenario    = "test-s3-access-via-policy-attachment-type"
    Purpose     = "test-principal-role-managed-policy"
  }
}

resource "aws_iam_role_policy_attachment" "role_managed" {
  provider   = aws.prod
  role       = aws_iam_role.role_managed.name
  policy_arn = aws_iam_policy.s3_access_managed_policy.arn
}
