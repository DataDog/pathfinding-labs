terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Test Reverse Blast Radius: Implicit Admin Access to Bucket
#
# A reverse blast radius query asks "who can read / write this bucket?". This
# scenario verifies that administrators whose access comes ONLY from
# administrative permissions (no S3-specific statement anywhere) are included
# in the answer.
#
# Principals:
#   reader-user     explicit s3:GetObject + s3:ListBucket on the bucket
#   writer-user     explicit s3:PutObject on the bucket
#   admin-user      AWS managed AdministratorAccess policy, no S3 statements
#   admin-role      inline Action "*" on Resource "*", no S3 statements
#   no-access-user  negative control, no policies at all
#
# Expected truth table:
#   can_read  bucket = reader-user, admin-user, admin-role
#                      (NOT writer-user, NOT no-access-user)
#   can_write bucket = writer-user, admin-user, admin-role
#                      (NOT reader-user, NOT no-access-user)
#
# The bucket intentionally has NO bucket policy, so all access is derived from
# identity policies only.
#
# Resource naming convention: pl-prod-rbr-ia-{purpose}

# =============================================================================
# TARGET S3 BUCKET (no bucket policy)
# =============================================================================

resource "aws_s3_bucket" "target_bucket" {
  provider      = aws.prod
  bucket        = "pl-sensitive-data-rbr-ia-${var.account_id}-${var.resource_suffix}"
  force_destroy = true

  tags = {
    Name        = "pl-sensitive-data-rbr-ia-bucket"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-implicit-admin-access"
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

# Sample object to demonstrate access
resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is sensitive data. Administrators with no S3-specific permissions should still appear in reverse blast radius results for this bucket."
}

# =============================================================================
# READER USER: explicit read-only access
# =============================================================================

resource "aws_iam_user" "reader_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-ia-reader-user"

  tags = {
    Name        = "pl-prod-rbr-ia-reader-user"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-implicit-admin-access"
    Purpose     = "explicit-read-user"
  }
}

resource "aws_iam_access_key" "reader_user_key" {
  provider = aws.prod
  user     = aws_iam_user.reader_user.name
}

resource "aws_iam_user_policy" "reader_user_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-ia-reader-user-policy"
  user     = aws_iam_user.reader_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationReadObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Sid      = "RequiredForExploitationListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.target_bucket.arn
      },
      {
        Sid      = "HelpfulForReconAndMonitoring"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# WRITER USER: explicit write-only access
# =============================================================================

resource "aws_iam_user" "writer_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-ia-writer-user"

  tags = {
    Name        = "pl-prod-rbr-ia-writer-user"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-implicit-admin-access"
    Purpose     = "explicit-write-user"
  }
}

resource "aws_iam_access_key" "writer_user_key" {
  provider = aws.prod
  user     = aws_iam_user.writer_user.name
}

resource "aws_iam_user_policy" "writer_user_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-ia-writer-user-policy"
  user     = aws_iam_user.writer_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationWriteObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.target_bucket.arn}/*"
      }
    ]
  })
}

# =============================================================================
# ADMIN USER: AdministratorAccess managed policy, no S3 statements
# =============================================================================

resource "aws_iam_user" "admin_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-ia-admin-user"

  tags = {
    Name        = "pl-prod-rbr-ia-admin-user"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-implicit-admin-access"
    Purpose     = "implicit-admin-user"
  }
}

resource "aws_iam_access_key" "admin_user_key" {
  provider = aws.prod
  user     = aws_iam_user.admin_user.name
}

resource "aws_iam_user_policy_attachment" "admin_user_admin_access" {
  provider   = aws.prod
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# =============================================================================
# ADMIN ROLE: inline Action "*" Resource "*", no S3 statements
# =============================================================================

# The trust policy trusts ONLY the EC2 service principal. No user, account
# root, or starting user is trusted, so no principal gains an assume-role edge
# into this role. Its access to the bucket therefore comes purely from its own
# administrative permissions, which is exactly what this scenario tests.
resource "aws_iam_role" "admin_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-rbr-ia-admin-role"

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
    Name        = "pl-prod-rbr-ia-admin-role"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-implicit-admin-access"
    Purpose     = "implicit-admin-role"
  }
}

# Inline wildcard grant (rather than the managed policy) to vary the grant style
resource "aws_iam_role_policy" "admin_role_policy" {
  provider = aws.prod
  name     = "pl-prod-rbr-ia-admin-role-policy"
  role     = aws_iam_role.admin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationAdminWildcard"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# NO-ACCESS USER: negative control, no policies
# =============================================================================

resource "aws_iam_user" "no_access_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-ia-no-access-user"

  tags = {
    Name        = "pl-prod-rbr-ia-no-access-user"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-implicit-admin-access"
    Purpose     = "negative-control-user"
  }
}

resource "aws_iam_access_key" "no_access_user_key" {
  provider = aws.prod
  user     = aws_iam_user.no_access_user.name
}
