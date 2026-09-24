terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# =============================================================================
# Tool Testing: S3 Read/Write/Delete Permission Edge Granularity
# =============================================================================
#
# This scenario creates 8 independent test principals (4 permission tiers x
# IAM user/role), each granted a precise, non-overlapping subset of
# s3:GetObject / s3:PutObject / s3:DeleteObject on the same S3 bucket:
#   - Read-only:  s3:GetObject + s3:ListBucket only
#   - Write-only: s3:PutObject only
#   - Delete-only: s3:DeleteObject only
#   - Read+Write+Delete: full CRUD access
#
# The point of the scenario is NOT bucket misconfiguration - the bucket is a
# plain private bucket. The point is to validate that a graph/CSPM tool's
# can_read/can_write/can_delete edges are set exactly per principal, with no
# principal showing an edge it wasn't actually granted (no over- or
# under-inference).
#
# A seed object is pre-created in the bucket via Terraform so the read-only
# and delete-only principals have something to act on without needing write
# access themselves.
#
# Resource naming convention: pl-prod-rwd-{principal-type}-{tier}

# =============================================================================
# TARGET S3 BUCKET
# =============================================================================

resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-rwd-bucket-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-rwd-bucket-${var.account_id}-${var.resource_suffix}"
    Environment = var.environment
    Scenario    = "test-s3-read-write-delete-permission-edges"
    Purpose     = "target-bucket"
  }
}

# Pre-existing seed object so read-only/delete-only principals have
# something to read/delete without needing write access themselves.
resource "aws_s3_object" "seed_object" {
  provider     = aws.prod
  bucket       = aws_s3_bucket.target_bucket.id
  key          = "seed-object.txt"
  content      = "placeholder content for read/write/delete permission edge testing"
  content_type = "text/plain"

  tags = {
    Name        = "pl-rwd-seed-object"
    Environment = var.environment
    Scenario    = "test-s3-read-write-delete-permission-edges"
    Purpose     = "seed-object"
  }
}

# =============================================================================
# STARTING USER
# =============================================================================
#
# The starting user's only job is to sts:AssumeRole into the four role-based
# test principals. It has no direct S3 access of its own.

resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-rwd-starting-user"

  tags = {
    Name        = "pl-prod-rwd-starting-user"
    Environment = var.environment
    Scenario    = "test-s3-read-write-delete-permission-edges"
    Purpose     = "starting-user-for-role-assumption"
  }
}

resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

resource "aws_iam_user_policy" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-rwd-starting-user-policy"
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
          aws_iam_role.role_read_only.arn,
          aws_iam_role.role_write_only.arn,
          aws_iam_role.role_delete_only.arn,
          aws_iam_role.role_read_write_delete.arn
        ]
      }
    ]
  })
}

# =============================================================================
# READ-ONLY TIER: s3:GetObject + s3:ListBucket only
# =============================================================================

resource "aws_iam_user" "user_read_only" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-rwd-user-read-only"

  tags = {
    Name        = "pl-prod-rwd-user-read-only"
    Environment = var.environment
    Scenario    = "test-s3-read-write-delete-permission-edges"
    Purpose     = "test-principal-read-only"
  }
}

resource "aws_iam_access_key" "user_read_only" {
  provider = aws.prod
  user     = aws_iam_user.user_read_only.name
}

resource "aws_iam_user_policy" "user_read_only" {
  provider = aws.prod
  name     = "pl-prod-rwd-user-read-only-policy"
  user     = aws_iam_user.user_read_only.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationGetObject"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid      = "RequiredForExploitationListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.target_bucket.arn
      }
    ]
  })
}

resource "aws_iam_role" "role_read_only" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-rwd-role-read-only"

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
    Name        = "pl-prod-rwd-role-read-only"
    Environment = var.environment
    Scenario    = "test-s3-read-write-delete-permission-edges"
    Purpose     = "test-principal-read-only"
  }
}

resource "aws_iam_role_policy" "role_read_only" {
  provider = aws.prod
  name     = "pl-prod-rwd-role-read-only-policy"
  role     = aws_iam_role.role_read_only.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationGetObject"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid      = "RequiredForExploitationListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.target_bucket.arn
      }
    ]
  })
}

# =============================================================================
# WRITE-ONLY TIER: s3:PutObject only
# =============================================================================

resource "aws_iam_user" "user_write_only" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-rwd-user-write-only"

  tags = {
    Name        = "pl-prod-rwd-user-write-only"
    Environment = var.environment
    Scenario    = "test-s3-read-write-delete-permission-edges"
    Purpose     = "test-principal-write-only"
  }
}

resource "aws_iam_access_key" "user_write_only" {
  provider = aws.prod
  user     = aws_iam_user.user_write_only.name
}

resource "aws_iam_user_policy" "user_write_only" {
  provider = aws.prod
  name     = "pl-prod-rwd-user-write-only-policy"
  user     = aws_iam_user.user_write_only.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationPutObject"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role" "role_write_only" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-rwd-role-write-only"

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
    Name        = "pl-prod-rwd-role-write-only"
    Environment = var.environment
    Scenario    = "test-s3-read-write-delete-permission-edges"
    Purpose     = "test-principal-write-only"
  }
}

resource "aws_iam_role_policy" "role_write_only" {
  provider = aws.prod
  name     = "pl-prod-rwd-role-write-only-policy"
  role     = aws_iam_role.role_write_only.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationPutObject"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      }
    ]
  })
}

# =============================================================================
# DELETE-ONLY TIER: s3:DeleteObject only
# =============================================================================

resource "aws_iam_user" "user_delete_only" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-rwd-user-delete-only"

  tags = {
    Name        = "pl-prod-rwd-user-delete-only"
    Environment = var.environment
    Scenario    = "test-s3-read-write-delete-permission-edges"
    Purpose     = "test-principal-delete-only"
  }
}

resource "aws_iam_access_key" "user_delete_only" {
  provider = aws.prod
  user     = aws_iam_user.user_delete_only.name
}

resource "aws_iam_user_policy" "user_delete_only" {
  provider = aws.prod
  name     = "pl-prod-rwd-user-delete-only-policy"
  user     = aws_iam_user.user_delete_only.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationDeleteObject"
        Effect   = "Allow"
        Action   = "s3:DeleteObject"
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role" "role_delete_only" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-rwd-role-delete-only"

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
    Name        = "pl-prod-rwd-role-delete-only"
    Environment = var.environment
    Scenario    = "test-s3-read-write-delete-permission-edges"
    Purpose     = "test-principal-delete-only"
  }
}

resource "aws_iam_role_policy" "role_delete_only" {
  provider = aws.prod
  name     = "pl-prod-rwd-role-delete-only-policy"
  role     = aws_iam_role.role_delete_only.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationDeleteObject"
        Effect   = "Allow"
        Action   = "s3:DeleteObject"
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      }
    ]
  })
}

# =============================================================================
# READ+WRITE+DELETE TIER: full CRUD access
# =============================================================================

resource "aws_iam_user" "user_read_write_delete" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-rwd-user-read-write-delete"

  tags = {
    Name        = "pl-prod-rwd-user-read-write-delete"
    Environment = var.environment
    Scenario    = "test-s3-read-write-delete-permission-edges"
    Purpose     = "test-principal-read-write-delete"
  }
}

resource "aws_iam_access_key" "user_read_write_delete" {
  provider = aws.prod
  user     = aws_iam_user.user_read_write_delete.name
}

resource "aws_iam_user_policy" "user_read_write_delete" {
  provider = aws.prod
  name     = "pl-prod-rwd-user-read-write-delete-policy"
  user     = aws_iam_user.user_read_write_delete.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid      = "RequiredForExploitationListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.target_bucket.arn
      }
    ]
  })
}

resource "aws_iam_role" "role_read_write_delete" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-rwd-role-read-write-delete"

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
    Name        = "pl-prod-rwd-role-read-write-delete"
    Environment = var.environment
    Scenario    = "test-s3-read-write-delete-permission-edges"
    Purpose     = "test-principal-read-write-delete"
  }
}

resource "aws_iam_role_policy" "role_read_write_delete" {
  provider = aws.prod
  name     = "pl-prod-rwd-role-read-write-delete-policy"
  role     = aws_iam_role.role_read_write_delete.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid      = "RequiredForExploitationListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.target_bucket.arn
      }
    ]
  })
}
