# =============================================================================
# Tool-testing lab: test-reverse-blast-radius-bucket-policy
#
# Tests that a reverse-blast-radius answer for a bucket honors the bucket's
# resource policy in both directions: access GRANTED only by the bucket policy
# is found, and access DENIED by the bucket policy is withheld even from an
# administrator.
#
# Unlike the old exclusive-resource-policy lab, the Deny names specific
# principal ARNs (not deny-all-except), so there is NO deployer exemption and
# the expected answer is identical in every account (deterministic).
#
# Expected reverse-blast-radius for the bucket (can_read):
#   policy-granted-role  YES  (granted only by the bucket policy)
#   identity-reader      YES  (granted only by its identity policy)
#   starting-user        YES, at 1 hop (assumes policy-granted-role)
#   denied-reader        NO   (identity allows, but bucket policy Denies its ARN)
#   denied-admin         NO   (AdministratorAccess, but bucket policy Denies its ARN)
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
  bucket        = "pl-sensitive-data-rbr-bp-${var.account_id}-${var.resource_suffix}"
  force_destroy = true

  tags = {
    Name        = "pl-sensitive-data-rbr-bp"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-bucket-policy"
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
  content  = "Sensitive data for reverse-blast-radius bucket-policy testing.\n"
}

# -----------------------------------------------------------------------------
# Starting user: assumes the policy-granted role (gives the lab a 1-hop case)
# -----------------------------------------------------------------------------
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-bp-starting-user"
}

resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

resource "aws_iam_user_policy" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-rbr-bp-starting-user-policy"
  user     = aws_iam_user.starting_user.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationAssumeRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.policy_granted.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# policy-granted-role: NO S3 in its identity policy; access comes ONLY from the
# bucket policy. Trusts the starting user.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "policy_granted" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-rbr-bp-policy-granted-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = aws_iam_user.starting_user.arn }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "policy_granted" {
  provider = aws.prod
  name     = "pl-prod-rbr-bp-policy-granted-role-policy"
  role     = aws_iam_role.policy_granted.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "HelpfulForReconAndMonitoring"
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# identity-reader: reads via its OWN identity policy (bucket policy is silent
# about it). Control for the identity side.
# -----------------------------------------------------------------------------
resource "aws_iam_user" "identity_reader" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-bp-identity-reader"
}

resource "aws_iam_access_key" "identity_reader" {
  provider = aws.prod
  user     = aws_iam_user.identity_reader.name
}

resource "aws_iam_user_policy" "identity_reader" {
  provider = aws.prod
  name     = "pl-prod-rbr-bp-identity-reader-policy"
  user     = aws_iam_user.identity_reader.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationBucketRead"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.target.arn, "${aws_s3_bucket.target.arn}/*"]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# denied-reader: identity policy allows reading, but the bucket policy Denies
# this exact ARN. Effective access: none.
# -----------------------------------------------------------------------------
resource "aws_iam_user" "denied_reader" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-bp-denied-reader"
}

resource "aws_iam_access_key" "denied_reader" {
  provider = aws.prod
  user     = aws_iam_user.denied_reader.name
}

resource "aws_iam_user_policy" "denied_reader" {
  provider = aws.prod
  name     = "pl-prod-rbr-bp-denied-reader-policy"
  user     = aws_iam_user.denied_reader.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LooksLikeAReaderButBucketPolicyDenies"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.target.arn, "${aws_s3_bucket.target.arn}/*"]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# denied-admin: full AdministratorAccess, but the bucket policy Denies this
# exact ARN. An explicit resource-policy Deny overrides admin. Effective
# access to THIS bucket: none.
# -----------------------------------------------------------------------------
resource "aws_iam_user" "denied_admin" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-bp-denied-admin"
}

resource "aws_iam_access_key" "denied_admin" {
  provider = aws.prod
  user     = aws_iam_user.denied_admin.name
}

resource "aws_iam_user_policy_attachment" "denied_admin" {
  provider   = aws.prod
  user       = aws_iam_user.denied_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# -----------------------------------------------------------------------------
# Bucket policy: Allow the policy-granted role; explicitly Deny the two
# denied principals by ARN. No deny-all-except, so no deployer exemption.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "target" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target.id
  depends_on = [
    aws_iam_role.policy_granted,
    aws_iam_user.denied_reader,
    aws_iam_user.denied_admin,
    aws_s3_bucket_public_access_block.target,
  ]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "GrantPolicyGrantedRole"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.policy_granted.arn }
        Action    = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource  = [aws_s3_bucket.target.arn, "${aws_s3_bucket.target.arn}/*"]
      },
      {
        Sid       = "DenySpecificPrincipals"
        Effect    = "Deny"
        Principal = { AWS = [aws_iam_user.denied_reader.arn, aws_iam_user.denied_admin.arn] }
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.target.arn, "${aws_s3_bucket.target.arn}/*"]
      }
    ]
  })
}
