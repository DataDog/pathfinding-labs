terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod, aws.attacker]
    }
  }
}

# Data Pipeline data exfiltration scenario (to-bucket)
#
# This scenario demonstrates how a user with datapipeline permissions and iam:PassRole
# on a role that has read access to a sensitive S3 bucket can exfiltrate that data by
# creating a pipeline that runs arbitrary shell commands on EC2 instances. The exfil
# bucket is attacker-controlled infrastructure (deployed in the attacker account), not
# a victim misconfiguration.

# Resource naming convention: pl-prod-datapipeline-001-to-bucket-{resource-type}
# All resources use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-datapipeline-001-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-datapipeline-001-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+datapipeline-pipeline"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Pipeline role - trusted by DataPipeline service, has read-only S3 access
resource "aws_iam_role" "pipeline_role" {
  provider = aws.prod
  name     = "pl-prod-datapipeline-001-to-bucket-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "datapipeline.amazonaws.com",
            "elasticmapreduce.amazonaws.com",
            "ec2.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-datapipeline-001-to-bucket-pipeline-role"
    Environment = var.environment
    Scenario    = "iam-passrole+datapipeline-pipeline"
    Purpose     = "pipeline-role"
  }
}

# Pipeline role policy - ONLY read access to sensitive bucket (appears safe)
resource "aws_iam_role_policy" "pipeline_role_policy" {
  provider = aws.prod
  name     = "pl-prod-datapipeline-001-to-bucket-pipeline-policy"
  role     = aws_iam_role.pipeline_role.id

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
          aws_s3_bucket.sensitive_bucket.arn,
          "${aws_s3_bucket.sensitive_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:RunInstances",
          "ec2:TerminateInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# Sensitive bucket containing target data
resource "aws_s3_bucket" "sensitive_bucket" {
  provider = aws.prod
  bucket   = "pl-sensitive-data-datapipeline-001-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-sensitive-data-datapipeline-001"
    Environment = var.environment
    Scenario    = "iam-passrole+datapipeline-pipeline"
    Purpose     = "target-bucket"
  }
}

# Block public access on sensitive bucket
resource "aws_s3_bucket_public_access_block" "sensitive_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sensitive data to the target bucket
resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id
  key      = "secret-data.txt"
  content  = "CONFIDENTIAL: Database credentials and API keys for production systems."
}

# CTF flag stored as an S3 object in the target bucket. The attacker retrieves this after
# successfully reading data from the sensitive bucket via the pipeline role. Readable by
# any principal with s3:GetObject on this bucket.
resource "aws_s3_object" "flag" {
  provider = aws.prod
  bucket   = aws_s3_bucket.sensitive_bucket.id
  key      = "flag.txt"
  content  = var.flag_value
}

# Exfiltration bucket — attacker-controlled infrastructure deployed in the attacker account.
# This bucket receives stolen data from the pipeline EC2 instance. It is NOT a victim
# misconfiguration; it is something the attacker brings to the attack. When no separate
# attacker account is configured, aws.attacker falls back to the prod account, which is
# acceptable as a demo convenience but does not change the attack's narrative.
resource "aws_s3_bucket" "exfil_bucket" {
  provider = aws.attacker
  bucket   = "pl-exfil-bucket-datapipeline-001-${var.attacker_account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-exfil-bucket-datapipeline-001"
    Environment = var.environment
    Scenario    = "iam-passrole+datapipeline-pipeline"
    Purpose     = "attacker-controlled-exfil-bucket"
  }
}

# Block public access on exfil bucket — the bucket policy uses an explicit principal,
# not a wildcard, so public access blocks can stay fully enabled.
resource "aws_s3_bucket_public_access_block" "exfil_bucket" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.exfil_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Attacker-controlled bucket policy: grants the prod account root s3:PutObject so the
# pipeline EC2 instance (running in prod) can write exfiltrated data cross-account.
# This mirrors how glue-003/004/005/006 grant the prod account access to attacker buckets.
resource "aws_s3_bucket_policy" "exfil_bucket_policy" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.exfil_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowProdAccountWrite"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.exfil_bucket.arn}/*"
      }
    ]
  })
}

# Starting user policy - datapipeline permissions and PassRole on the pipeline role
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-datapipeline-001-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationDataPipeline"
        Effect = "Allow"
        Action = [
          "datapipeline:CreatePipeline",
          "datapipeline:PutPipelineDefinition",
          "datapipeline:ActivatePipeline"
        ]
        Resource = "*"
      },
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.pipeline_role.arn
      },
      {
        # Lets the demo read the attacker-controlled exfil bucket as the starting user
        # when no separate attacker account is configured (the bucket then lives in prod
        # and there is no real attacker principal to act as). In cross-account mode this
        # statement is unused — the demo uses real attacker-account credentials instead.
        Sid    = "LabSimulationReadExfilBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.exfil_bucket.arn,
          "${aws_s3_bucket.exfil_bucket.arn}/*"
        ]
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "datapipeline:DescribePipelines",
          "datapipeline:GetPipelineDefinition"
        ]
        Resource = "*"
      }
    ]
  })
}
