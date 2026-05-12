terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod, aws.attacker]
    }
  }
}

# iam-passrole+kinesisanalytics-createapplication+kinesisanalytics-startapplication privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, kinesisanalytics:CreateApplication,
# and kinesisanalytics:StartApplication can escalate privileges by:
# 1. Creating a Managed Apache Flink application referencing a malicious JAR in S3
# 2. Starting the application, passing an admin service execution role via iam:PassRole
# 3. The Flink application runs with admin permissions and attaches AdministratorAccess to the starting user
# 4. Starting user now has admin access
#
# Cost: ~$0/mo at rest (IAM user, role, and S3 bucket with small JAR; no always-on compute)
# Flink apps only incur cost when running.

# Resource naming convention: pl-prod-kinesisanalytics-001-to-admin-{resource-type}
# kinesisanalytics-001 = pathfinding.cloud ID for this scenario

# =============================================================================
# S3 BUCKET FOR FLINK APPLICATION CODE (ATTACKER-CONTROLLED)
# =============================================================================

# S3 bucket to hold the malicious Flink JAR. The Managed Apache Flink service
# reads the JAR from S3 when starting the application. Using S3ContentLocation
# instead of ZipFileContent because the Kinesis Analytics v2 API's inline
# validation rejects fat JARs that don't match its expected structure.
resource "aws_s3_bucket" "flink_code" {
  provider      = aws.attacker
  bucket        = "pl-kinesisanalytics-001-code-${var.attacker_account_id}-${var.resource_suffix}"
  force_destroy = true

  tags = {
    Name        = "pl-kinesisanalytics-001-code"
    Environment = var.environment
    Scenario    = "iam-passrole+kinesisanalytics-createapplication+kinesisanalytics-startapplication"
    Purpose     = "flink-application-code"
  }
}

# Block public access to the attacker bucket
resource "aws_s3_bucket_public_access_block" "flink_code_pab" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.flink_code.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload the pre-built exploit JAR to S3
resource "aws_s3_object" "exploit_jar" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.flink_code.id
  key      = "exploit.jar"
  source   = "${path.module}/exploit-jar/exploit.jar"
  etag     = filemd5("${path.module}/exploit-jar/exploit.jar")
}

# Bucket policy granting read access to all principals in the prod account
# This simulates an attacker-controlled bucket that grants access to specific accounts
resource "aws_s3_bucket_policy" "flink_code_policy" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.flink_code.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowProdAccountObjectAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.flink_code.arn}/*"
      },
      {
        Sid    = "AllowProdAccountListBucket"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.flink_code.arn
      }
    ]
  })
}

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  name          = "pl-prod-kinesisanalytics-001-to-admin-starting-user"
  force_destroy = true

  tags = {
    Name        = "pl-prod-kinesisanalytics-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+kinesisanalytics-createapplication+kinesisanalytics-startapplication"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Required permissions policy for exploitation
resource "aws_iam_user_policy" "starting_user_required" {
  provider = aws.prod
  name     = "pl-prod-kinesisanalytics-001-to-admin-required-permissions"
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
        Resource = aws_iam_role.admin_role.arn
      },
      {
        Sid    = "RequiredForExploitationKinesisAnalytics"
        Effect = "Allow"
        Action = [
          "kinesisanalytics:CreateApplication",
          "kinesisanalytics:StartApplication"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ADMIN ROLE (Privilege Escalation Target)
# =============================================================================

# Admin role that will be passed as the service execution role for the Flink application.
# This role trusts kinesisanalytics.amazonaws.com because Managed Apache Flink (formerly
# Kinesis Data Analytics v2) assumes it to run Flink applications.
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-kinesisanalytics-001-to-admin-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-kinesisanalytics-001-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+kinesisanalytics-createapplication+kinesisanalytics-startapplication"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess policy to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
