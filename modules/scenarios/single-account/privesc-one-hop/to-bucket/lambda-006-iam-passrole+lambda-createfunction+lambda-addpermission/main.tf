terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + lambda:CreateFunction + lambda:AddPermission privilege escalation scenario (to-bucket)
#
# This scenario demonstrates how a user with iam:PassRole, lambda:CreateFunction,
# lambda:AddPermission, and lambda:InvokeFunction can create a new Lambda function
# carrying a role that has S3 read access, add an invoke permission so their own
# user identity can call it, invoke the function, and retrieve the CTF flag from the
# target S3 bucket via the Lambda's execution role.
#
# The attacker does NOT update any pre-existing function — they create a net-new one
# during the demo. Terraform only provisions the starting user, the target role, and
# the S3 bucket.

# Resource naming convention: pl-prod-lambda-006-to-bucket-{purpose}
# All resources use provider = aws.prod

# =============================================================================
# SCENARIO-SPECIFIC STARTING USER
# =============================================================================

# force_destroy = true lets Terraform clean up any policies, access keys,
# login profiles, or group memberships the demo attaches out-of-band so
# destroy still succeeds if the user disables the scenario without first
# running cleanup_attack.sh.
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-lambda-006-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-lambda-006-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+lambda-addpermission"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting the required exploitable permissions and helpful recon permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-006-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "RequiredForExploitationLambda"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:AddPermission",
          "lambda:InvokeFunction"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "lambda:GetFunction",
          "lambda:GetPolicy",
          "lambda:DeleteFunction"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ROLE WITH S3 ACCESS
# =============================================================================

# Target role that the attacker will pass to their newly created Lambda function.
# Trusts lambda.amazonaws.com so the Lambda service can assume it at execution time.
# force_detach_policies = true is the role equivalent of force_destroy on
# aws_iam_user: it lets Terraform detach managed policies the demo may
# attach out-of-band so destroy succeeds without a prior cleanup run.
resource "aws_iam_role" "target_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-lambda-006-to-bucket-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-lambda-006-to-bucket-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+lambda-addpermission"
    Purpose     = "target-role"
  }
}

# Grant the target role read access to the sensitive S3 bucket so the Lambda
# function the attacker creates can retrieve flag.txt.
resource "aws_iam_role_policy" "target_role_s3_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-006-to-bucket-target-s3-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.target_bucket.arn,
          "${aws_s3_bucket.target_bucket.arn}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# TARGET S3 BUCKET WITH SENSITIVE DATA
# =============================================================================

# Target S3 bucket containing the CTF flag. Private; only the target_role can
# read objects inside it. The attacker accesses it by creating a Lambda function
# that executes with that role.
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-lambda-006-to-bucket-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-prod-lambda-006-to-bucket-bucket"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+lambda-addpermission"
    Purpose     = "target-bucket"
  }
}

# Block public access — the bucket is intentionally private; access is only possible
# through the target role carried by the attacker's Lambda function.
resource "aws_s3_bucket_public_access_block" "target_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Decoy sensitive file to make the bucket feel realistic during recon.
resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is sensitive data that should only be accessible to authorized principals."
}

# CTF flag stored as an S3 object in the target bucket. The attacker retrieves this
# by creating a Lambda function with the target role, adding an invoke permission
# granting their own user the right to call it, invoking the function, and reading
# the flag from the Lambda response. No extra IAM permissions are needed — any
# principal that can assume the target role (or run code as it) already has
# s3:GetObject on this bucket.
resource "aws_s3_object" "flag" {
  provider     = aws.prod
  bucket       = aws_s3_bucket.target_bucket.id
  key          = "flag.txt"
  content      = var.flag_value
  content_type = "text/plain"

  tags = {
    Name        = "pl-prod-lambda-006-to-bucket-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+lambda-addpermission"
    Purpose     = "ctf-flag"
  }
}
