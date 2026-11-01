# =============================================================================
# Tool-testing lab: test-reverse-blast-radius-assume-role-edges
#
# Tests that a tool builds the can_assume edge correctly. A same-account
# sts:AssumeRole requires BOTH an identity-based permission on the caller AND a
# trust policy on the role that allows the caller. A trust policy that grants to
# the account root defers entirely to identity policies.
#
# Two roles read the target bucket. Five candidate users differ only in which
# half of the assume-role requirement they satisfy:
#
#   user                       identity sts:AssumeRole   role trust allows   can assume?
#   are-both                   yes (explicit role)       yes (names user)    YES
#   are-identity-only          yes (explicit role)       no                  NO  (false-positive if tool reads only identity policies)
#   are-trust-only             no                        yes (names user)    NO  (false-positive if tool reads only trust policies)
#   are-root-with-identity     yes (root-trust role)     yes (root)          YES
#   are-root-no-identity       no                        yes (root)          NO  (root trust defers to identity, which is silent)
#
# Reverse-blast-radius "who can read the bucket via one assume-role hop" must
# return only are-both and are-root-with-identity.
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
  bucket        = "pl-sensitive-data-rbr-are-${var.account_id}-${var.resource_suffix}"
  force_destroy = true

  tags = {
    Name        = "pl-sensitive-data-rbr-are"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-assume-role-edges"
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
  content  = "Sensitive data for reverse-blast-radius assume-role-edge testing.\n"
}

# Inline S3-read policy shared by both target roles (as a document reused below).
locals {
  bucket_read_statement = {
    Sid      = "RequiredForExploitationBucketRead"
    Effect   = "Allow"
    Action   = ["s3:GetObject", "s3:ListBucket"]
    Resource = [aws_s3_bucket.target.arn, "${aws_s3_bucket.target.arn}/*"]
  }
}

# -----------------------------------------------------------------------------
# target-role: reads the bucket. Trust names exactly are-both and are-trust-only.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "target" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-rbr-are-target-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = [aws_iam_user.are_both.arn, aws_iam_user.are_trust_only.arn] }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "target" {
  provider = aws.prod
  name     = "pl-prod-rbr-are-target-role-policy"
  role     = aws_iam_role.target.id
  policy   = jsonencode({ Version = "2012-10-17", Statement = [local.bucket_read_statement] })
}

# -----------------------------------------------------------------------------
# target-role-root: reads the bucket. Trust grants to the account root, which
# defers the decision to callers' identity policies.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "target_root" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-rbr-are-target-role-root"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "target_root" {
  provider = aws.prod
  name     = "pl-prod-rbr-are-target-role-root-policy"
  role     = aws_iam_role.target_root.id
  policy   = jsonencode({ Version = "2012-10-17", Statement = [local.bucket_read_statement] })
}

# -----------------------------------------------------------------------------
# Candidate users. Each has an access key. Identity policies vary per the table.
# -----------------------------------------------------------------------------

# are-both: identity allows AssumeRole on target-role; trust names it. CAN.
resource "aws_iam_user" "are_both" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-are-both"
}
resource "aws_iam_access_key" "are_both" {
  provider = aws.prod
  user     = aws_iam_user.are_both.name
}
resource "aws_iam_user_policy" "are_both" {
  provider = aws.prod
  name     = "pl-prod-rbr-are-both-policy"
  user     = aws_iam_user.are_both.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "RequiredForExploitationAssumeRole", Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.target.arn }]
  })
}

# are-identity-only: identity allows AssumeRole on target-role; trust does NOT name it. CANNOT.
resource "aws_iam_user" "are_identity_only" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-are-identity-only"
}
resource "aws_iam_access_key" "are_identity_only" {
  provider = aws.prod
  user     = aws_iam_user.are_identity_only.name
}
resource "aws_iam_user_policy" "are_identity_only" {
  provider = aws.prod
  name     = "pl-prod-rbr-are-identity-only-policy"
  user     = aws_iam_user.are_identity_only.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "IdentityAllowsButTrustDenies", Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.target.arn }]
  })
}

# are-trust-only: trust names it; identity has NO AssumeRole permission. CANNOT.
# Given a harmless identity permission so the user is usable for recon only.
resource "aws_iam_user" "are_trust_only" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-are-trust-only"
}
resource "aws_iam_access_key" "are_trust_only" {
  provider = aws.prod
  user     = aws_iam_user.are_trust_only.name
}
resource "aws_iam_user_policy" "are_trust_only" {
  provider = aws.prod
  name     = "pl-prod-rbr-are-trust-only-policy"
  user     = aws_iam_user.are_trust_only.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "HelpfulForReconAndMonitoring", Effect = "Allow", Action = "sts:GetCallerIdentity", Resource = "*" }]
  })
}

# are-root-with-identity: identity allows AssumeRole on target-role-root; root trust defers to it. CAN.
resource "aws_iam_user" "are_root_with_identity" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-are-root-with-identity"
}
resource "aws_iam_access_key" "are_root_with_identity" {
  provider = aws.prod
  user     = aws_iam_user.are_root_with_identity.name
}
resource "aws_iam_user_policy" "are_root_with_identity" {
  provider = aws.prod
  name     = "pl-prod-rbr-are-root-with-identity-policy"
  user     = aws_iam_user.are_root_with_identity.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "RequiredForExploitationAssumeRole", Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.target_root.arn }]
  })
}

# are-root-no-identity: root trust, but identity is silent on AssumeRole. CANNOT.
resource "aws_iam_user" "are_root_no_identity" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-are-root-no-identity"
}
resource "aws_iam_access_key" "are_root_no_identity" {
  provider = aws.prod
  user     = aws_iam_user.are_root_no_identity.name
}
resource "aws_iam_user_policy" "are_root_no_identity" {
  provider = aws.prod
  name     = "pl-prod-rbr-are-root-no-identity-policy"
  user     = aws_iam_user.are_root_no_identity.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "HelpfulForReconAndMonitoring", Effect = "Allow", Action = "sts:GetCallerIdentity", Resource = "*" }]
  })
}
