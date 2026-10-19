terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# Test Reverse Blast Radius - Hop Depth to Bucket
#
# Purpose: show that "who can read this bucket" must be asked at several hop
# depths, because each query depth returns different principals.
#
# Graph (arrows = can assume):
#
#   user-a  --direct S3-->  bucket                       (depth 0)
#   role-r1 --direct S3-->  bucket                       (depth 0)
#   user-b  --assume--> role-r1 --> bucket               (depth 1)
#   role-r2 --assume--> role-r1 --> bucket               (depth 1)
#   user-c  --assume--> role-r2 --> role-r1 --> bucket   (depth 2)
#
# Expected truth table (who can read the bucket):
#   exactly 0 hops: user-a, role-r1
#   exactly 1 hop:  user-b, role-r2
#   exactly 2 hops: user-c
#   cumulative (<= 1 hop): user-a, role-r1, user-b, role-r2
#   cumulative (<= 2 hops): user-a, role-r1, user-b, role-r2, user-c
#
# Trust policies name specific principal ARNs (never account root) so that no
# unintended principal can assume either role. The bucket has NO bucket policy.
#
# Resource naming convention: pl-prod-rbr-hd-{purpose}
# Use provider = aws.prod for all resources

# =============================================================================
# TARGET S3 BUCKET
# =============================================================================

resource "aws_s3_bucket" "target_bucket" {
  provider      = aws.prod
  bucket        = "pl-sensitive-data-rbr-hd-${var.account_id}-${var.resource_suffix}"
  force_destroy = true

  tags = {
    Name        = "pl-sensitive-data-rbr-hd-bucket"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-hop-depth"
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

resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is sensitive data that should only be accessible to authorized principals. Who can read it depends on how many role-assumption hops you are willing to follow."
}

# =============================================================================
# DEPTH 0: user-a (direct S3 access)
# =============================================================================

resource "aws_iam_user" "user_a" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-hd-user-a"

  tags = {
    Name        = "pl-prod-rbr-hd-user-a"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-hop-depth"
    Purpose     = "depth-0-direct-user"
  }
}

resource "aws_iam_access_key" "user_a_key" {
  provider = aws.prod
  user     = aws_iam_user.user_a.name
}

# Direct S3 read access, no assume-role permission
resource "aws_iam_user_policy" "user_a_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-hd-user-a-policy"
  user     = aws_iam_user.user_a.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationBucketObjectRead"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid      = "RequiredForExploitationBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.target_bucket.arn
      },
      {
        Sid      = "HelpfulForReconAndMonitoring"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
    ]
  })
}

# =============================================================================
# DEPTH 0: role-r1 (direct S3 access; assumable by user-b and role-r2 only)
# =============================================================================

# The trust policy references user-b and role-r2 ARNs directly. IAM validates
# that trusted principals exist, so Terraform creates them first via the
# implicit dependency. Role permission policies are separate
# aws_iam_role_policy resources so role-r2's policy (which references role-r1)
# does not create a dependency cycle with role-r1's trust policy.
resource "aws_iam_role" "role_r1" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-rbr-hd-role-r1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = [
          aws_iam_user.user_b.arn,
          aws_iam_role.role_r2.arn,
        ]
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-rbr-hd-role-r1"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-hop-depth"
    Purpose     = "depth-0-direct-role"
  }
}

resource "aws_iam_role_policy" "role_r1_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-hd-role-r1-policy"
  role     = aws_iam_role.role_r1.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationBucketObjectRead"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid      = "RequiredForExploitationBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.target_bucket.arn
      },
    ]
  })
}

# =============================================================================
# DEPTH 1: user-b (assume role-r1)
# =============================================================================

resource "aws_iam_user" "user_b" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-hd-user-b"

  tags = {
    Name        = "pl-prod-rbr-hd-user-b"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-hop-depth"
    Purpose     = "depth-1-user"
  }
}

resource "aws_iam_access_key" "user_b_key" {
  provider = aws.prod
  user     = aws_iam_user.user_b.name
}

# ONLY sts:AssumeRole on role-r1, no S3 permissions
resource "aws_iam_user_policy" "user_b_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-hd-user-b-policy"
  user     = aws_iam_user.user_b.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationAssumeRoleR1"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.role_r1.arn
      },
    ]
  })
}

# =============================================================================
# DEPTH 1: role-r2 (assume role-r1; assumable by user-c only)
# =============================================================================

resource "aws_iam_role" "role_r2" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-rbr-hd-role-r2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = aws_iam_user.user_c.arn
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-rbr-hd-role-r2"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-hop-depth"
    Purpose     = "depth-1-role"
  }
}

# ONLY sts:AssumeRole on role-r1, no S3 permissions
resource "aws_iam_role_policy" "role_r2_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-hd-role-r2-policy"
  role     = aws_iam_role.role_r2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationAssumeRoleR1"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.role_r1.arn
      },
    ]
  })
}

# =============================================================================
# DEPTH 2: user-c (assume role-r2, which assumes role-r1)
# =============================================================================

resource "aws_iam_user" "user_c" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-hd-user-c"

  tags = {
    Name        = "pl-prod-rbr-hd-user-c"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-hop-depth"
    Purpose     = "depth-2-user"
  }
}

resource "aws_iam_access_key" "user_c_key" {
  provider = aws.prod
  user     = aws_iam_user.user_c.name
}

# ONLY sts:AssumeRole on role-r2, no S3 permissions
resource "aws_iam_user_policy" "user_c_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-hd-user-c-policy"
  user     = aws_iam_user.user_c.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationAssumeRoleR2"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.role_r2.arn
      },
    ]
  })
}
