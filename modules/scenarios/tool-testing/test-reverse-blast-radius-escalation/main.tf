# =============================================================================
# Tool-testing lab: test-reverse-blast-radius-escalation
#
# Tests the "including privilege escalations" form of reverse blast radius:
# principals that cannot read the bucket today but can grant themselves the
# ability to. A direct-only query must NOT return them; an escalation-aware
# query must.
#
#   bucket-reader     reads the bucket directly                              (direct)
#   cak-user          iam:CreateAccessKey on bucket-reader -> act as it      (escalate)
#   attach-self-user  iam:AttachUserPolicy on self -> attach admin -> read   (escalate)
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
  bucket        = "pl-sensitive-data-rbr-esc-${var.account_id}-${var.resource_suffix}"
  force_destroy = true

  tags = {
    Name        = "pl-sensitive-data-rbr-esc"
    Environment = var.environment
    Scenario    = "test-reverse-blast-radius-escalation"
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
  content  = "Sensitive data for reverse-blast-radius escalation testing.\n"
}

# bucket-reader: reads the bucket directly (the escalation target).
resource "aws_iam_user" "bucket_reader" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-esc-bucket-reader"
}
resource "aws_iam_access_key" "bucket_reader" {
  provider = aws.prod
  user     = aws_iam_user.bucket_reader.name
}
resource "aws_iam_user_policy" "bucket_reader" {
  provider = aws.prod
  name     = "pl-prod-rbr-esc-bucket-reader-policy"
  user     = aws_iam_user.bucket_reader.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "RequiredForExploitationBucketRead"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.target.arn, "${aws_s3_bucket.target.arn}/*"]
    }]
  })
}

# cak-user: can mint access keys for bucket-reader, then act as it. No S3 itself.
resource "aws_iam_user" "cak_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-esc-cak-user"
}
resource "aws_iam_access_key" "cak_user" {
  provider = aws.prod
  user     = aws_iam_user.cak_user.name
}
resource "aws_iam_user_policy" "cak_user" {
  provider = aws.prod
  name     = "pl-prod-rbr-esc-cak-user-policy"
  user     = aws_iam_user.cak_user.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "EscalateViaCreateAccessKey"
      Effect   = "Allow"
      Action   = "iam:CreateAccessKey"
      Resource = aws_iam_user.bucket_reader.arn
    }]
  })
}

# attach-self-user: can attach any managed policy to itself -> attach admin -> read. No S3 itself.
resource "aws_iam_user" "attach_self_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-rbr-esc-attach-self-user"
}
resource "aws_iam_access_key" "attach_self_user" {
  provider = aws.prod
  user     = aws_iam_user.attach_self_user.name
}
resource "aws_iam_user_policy" "attach_self_user" {
  provider = aws.prod
  name     = "pl-prod-rbr-esc-attach-self-user-policy"
  user     = aws_iam_user.attach_self_user.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "EscalateViaAttachUserPolicy"
      Effect   = "Allow"
      Action   = "iam:AttachUserPolicy"
      Resource = aws_iam_user.attach_self_user.arn
    }]
  })
}
