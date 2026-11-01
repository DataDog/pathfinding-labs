# =============================================================================
# Tool-testing lab: test-reverse-blast-radius-identity-side-block
#
# The resource-access analog of the admin-classification lab: a principal that
# looks like a bucket reader can still be blocked on the IDENTITY side, by an
# explicit deny or by a permissions boundary. A reverse-blast-radius answer must
# exclude such principals.
#
#   plain-reader          Allow s3 read, nothing blocking        -> YES (control)
#   explicit-deny-reader  Allow s3 read + inline Deny s3:*        -> NO
#   boundary-excludes-s3  Allow s3 read + EC2-only boundary       -> NO
# =============================================================================

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

resource "aws_s3_bucket" "target" {
  provider      = aws.prod
  bucket        = "pl-sensitive-data-rbr-isb-${var.account_id}-${var.resource_suffix}"
  force_destroy = true

  tags = {
    Name        = "pl-sensitive-data-rbr-isb"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-identity-side-block"
  }
}

resource "aws_s3_bucket_public_access_block" "target" {
  provider                = aws.prod
  bucket                  = aws_s3_bucket.target.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target.id
  key      = "sensitive-data.txt"
  content  = "Sensitive data for reverse-blast-radius identity-side-block testing.\n"
}

locals {
  bucket_read_statement = {
    Sid      = "LooksLikeAReader"
    Effect   = "Allow"
    Action   = ["s3:GetObject", "s3:ListBucket"]
    Resource = [aws_s3_bucket.target.arn, "${aws_s3_bucket.target.arn}/*"]
  }
}

# Permissions boundary that allows only EC2 — excludes S3 entirely.
resource "aws_iam_policy" "ec2_only_boundary" {
  provider = aws.prod
  name     = "pl-prod-rbr-isb-ec2-only-boundary"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "Ec2OnlyBoundary", Effect = "Allow", Action = "ec2:Describe*", Resource = "*" }]
  })
}

# plain-reader: control; reads the bucket.
resource "aws_iam_user" "plain_reader" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-isb-plain-reader"
}
resource "aws_iam_access_key" "plain_reader" {
  provider = aws.prod
  user     = aws_iam_user.plain_reader.name
}
resource "aws_iam_user_policy" "plain_reader" {
  provider = aws.prod
  name     = "pl-prod-rbr-isb-plain-reader-policy"
  user     = aws_iam_user.plain_reader.name
  policy   = jsonencode({ Version = "2012-10-17", Statement = [local.bucket_read_statement] })
}

# explicit-deny-reader: Allow s3 read + inline Deny s3:* (deny wins).
resource "aws_iam_user" "explicit_deny_reader" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-isb-explicit-deny-reader"
}
resource "aws_iam_access_key" "explicit_deny_reader" {
  provider = aws.prod
  user     = aws_iam_user.explicit_deny_reader.name
}
resource "aws_iam_user_policy" "explicit_deny_reader" {
  provider = aws.prod
  name     = "pl-prod-rbr-isb-explicit-deny-reader-policy"
  user     = aws_iam_user.explicit_deny_reader.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.bucket_read_statement,
      { Sid = "ExplicitDenyWins", Effect = "Deny", Action = "s3:*", Resource = "*" }
    ]
  })
}

# boundary-excludes-s3: Allow s3 read, but EC2-only boundary caps effective perms.
resource "aws_iam_user" "boundary_excludes_s3" {
  provider             = aws.prod
  force_destroy        = true
  name                 = "pl-prod-rbr-isb-boundary-excludes-s3"
  permissions_boundary = aws_iam_policy.ec2_only_boundary.arn
}
resource "aws_iam_access_key" "boundary_excludes_s3" {
  provider = aws.prod
  user     = aws_iam_user.boundary_excludes_s3.name
}
resource "aws_iam_user_policy" "boundary_excludes_s3" {
  provider = aws.prod
  name     = "pl-prod-rbr-isb-boundary-excludes-s3-policy"
  user     = aws_iam_user.boundary_excludes_s3.name
  policy   = jsonencode({ Version = "2012-10-17", Statement = [local.bucket_read_statement] })
}
