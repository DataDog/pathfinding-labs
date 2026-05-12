terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod, aws.attacker]
    }
  }
}

# iam-passrole+omics-createworkflow+omics-startrun privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, omics:CreateWorkflow,
# and omics:StartRun can escalate privileges by:
# 1. Creating a HealthOmics WDL workflow that exfiltrates role credentials to S3
# 2. Starting a workflow run that passes an admin role via iam:PassRole
# 3. The workflow task runs with admin credentials but can only access S3/ECR/KMS/CloudWatch/Omics
# 4. The WDL task writes the admin role's temporary credentials to the S3 bucket
# 5. The attacker retrieves the credentials from S3 and uses them locally for full admin access
#
# IMPORTANT: HealthOmics workflow tasks have network isolation - they cannot call IAM APIs directly.
# The credential exfiltration pattern (via S3) is required to exploit the admin role's permissions.
#
# Cost: $0/mo at rest (IAM + S3 bucket only, no compute until workflow is run)

# Resource naming convention: pl-prod-omics-001-to-admin-{resource-type}
# omics-001 = pathfinding.cloud ID for this scenario

# Current region (needed for constructing ECR image URIs)
data "aws_region" "current" {
  provider = aws.prod
}

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-omics-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-omics-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+omics-createworkflow+omics-startrun"
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
  name     = "pl-prod-omics-001-to-admin-required-permissions"
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
        Sid    = "RequiredForExploitationOmics"
        Effect = "Allow"
        Action = [
          "omics:CreateWorkflow",
          "omics:StartRun"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ADMIN ROLE (Privilege Escalation Target)
# =============================================================================

# Admin role that will be passed as the run role for the HealthOmics workflow run.
# This role trusts omics.amazonaws.com because HealthOmics assumes it to execute workflow tasks.
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-omics-001-to-admin-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "omics.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-omics-001-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+omics-createworkflow+omics-startrun"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess policy to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# The admin role also needs S3 access to the output bucket so HealthOmics
# can write workflow outputs and the exfiltrated credentials.
# The bucket is in the attacker account, but IAM policy + bucket policy together grant access.
resource "aws_iam_role_policy" "admin_role_s3_access" {
  provider = aws.prod
  name     = "pl-prod-omics-001-to-admin-admin-role-s3-access"
  role     = aws_iam_role.admin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "readWriteOutputBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.output.arn}/*"
      },
      {
        Sid    = "listOutputBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.output.arn
      }
    ]
  })
}

# =============================================================================
# S3 BUCKET (Attacker-controlled exfiltration bucket)
# =============================================================================

# S3 bucket for HealthOmics workflow output storage and credential exfiltration.
# This bucket lives in the attacker account. HealthOmics requires an S3 output
# location for workflow runs. The WDL workflow task will also write the admin
# role's temporary credentials here.
resource "aws_s3_bucket" "output" {
  provider      = aws.attacker
  bucket        = "pl-prod-omics-001-to-admin-output-${var.attacker_account_id}-${var.resource_suffix}"
  force_destroy = true

  tags = {
    Name        = "pl-prod-omics-001-to-admin-output"
    Environment = var.environment
    Scenario    = "iam-passrole+omics-createworkflow+omics-startrun"
    Purpose     = "workflow-output-and-credential-exfiltration"
  }
}

# Block public access to the output bucket
resource "aws_s3_bucket_public_access_block" "output" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cross-account bucket policy granting the prod account access to read/write.
# The HealthOmics service role (in prod) writes workflow output and exfiltrated
# credentials. The attacker (or readonly user) reads them back.
resource "aws_s3_bucket_policy" "output_cross_account" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.output.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowProdAccountReadWrite"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.output.arn}/*"
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
        Resource = aws_s3_bucket.output.arn
      }
    ]
  })
}

# =============================================================================
# ECR REPOSITORY (Required for HealthOmics Container Images)
# =============================================================================

# HealthOmics requires private ECR image URIs -- it cannot pull from public registries
# directly. We create the ECR repo in the attacker account (which falls back to prod
# when no attacker account is configured). The demo script uses Docker locally to
# seed the repo with the public aws-cli image on first run.

resource "aws_ecr_repository" "workflow_image" {
  provider             = aws.attacker
  name                 = "pl-prod-omics-001-to-admin-aws-cli"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = {
    Name        = "pl-prod-omics-001-to-admin-workflow-image"
    Environment = var.environment
    Scenario    = "iam-passrole+omics-createworkflow+omics-startrun"
    Purpose     = "healthomics-workflow-container-image"
  }
}

# Grant the HealthOmics service AND the prod account permission to pull images.
# The prod account root principal is required for cross-account pulls (when the ECR
# repo lives in a separate attacker account). In single-account mode it's harmless.
resource "aws_ecr_repository_policy" "workflow_image_omics_access" {
  provider   = aws.attacker
  repository = aws_ecr_repository.workflow_image.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowOmicsImagePull"
        Effect = "Allow"
        Principal = {
          Service = "omics.amazonaws.com"
          AWS     = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
      }
    ]
  })
}
