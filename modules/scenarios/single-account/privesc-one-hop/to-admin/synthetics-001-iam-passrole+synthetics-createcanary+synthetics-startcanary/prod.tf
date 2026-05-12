# PassRole + Synthetics CreateCanary + StartCanary privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, synthetics:CreateCanary,
# and synthetics:StartCanary can escalate to admin by creating a CloudWatch Synthetics
# canary with malicious Python code (pre-staged in an attacker-controlled S3 bucket)
# and an admin execution role. When the canary runs, its underlying Lambda function
# executes with the admin role, attaching AdministratorAccess to the starting user.

# Resource naming convention: pl-prod-synthetics-001-to-admin-{resource-type}
# synthetics-001 = pathfinding.cloud ID for PassRole + Synthetics CreateCanary + StartCanary

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod, aws.attacker]
    }
  }
}

# =============================================================================
# STARTING USER
# =============================================================================

# Scenario-specific starting user with privilege escalation permissions
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-synthetics-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-synthetics-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+synthetics-createcanary+synthetics-startcanary"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# =============================================================================
# ADMIN ROLE (TARGET)
# =============================================================================

# Admin role trusted by lambda.amazonaws.com (canaries run as Lambda functions)
# This is the role that will be passed to the canary via iam:PassRole
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-synthetics-001-to-admin-admin-role"

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
    Name        = "pl-prod-synthetics-001-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+synthetics-createcanary+synthetics-startcanary"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# The admin role also needs operational permissions for the canary to function.
# Without these, the canary Lambda will fail before our malicious code runs.
resource "aws_iam_role_policy" "admin_role_canary_operations" {
  provider = aws.prod
  name     = "pl-prod-synthetics-001-to-admin-canary-operations"
  role     = aws_iam_role.admin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "canaryArtifactStorage"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::cw-syn-results-*",
          "arn:aws:s3:::cw-syn-results-*/*"
        ]
      },
      {
        Sid    = "canaryLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:${var.account_id}:log-group:/aws/lambda/cwsyn-*"
      },
      {
        Sid    = "canaryMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "CloudWatchSynthetics"
          }
        }
      }
    ]
  })
}

# =============================================================================
# S3 BUCKET FOR CANARY ARTIFACTS (SERVICE INFRASTRUCTURE - stays on prod)
# =============================================================================

# Synthetics canaries require an S3 bucket matching cw-syn-results-* for artifacts
resource "aws_s3_bucket" "canary_artifacts" {
  provider = aws.prod
  bucket   = "cw-syn-results-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "cw-syn-results-${var.account_id}-${var.resource_suffix}"
    Environment = var.environment
    Scenario    = "iam-passrole+synthetics-createcanary+synthetics-startcanary"
    Purpose     = "canary-artifacts"
  }
}

# Block public access on the canary artifacts bucket
resource "aws_s3_bucket_public_access_block" "canary_artifacts" {
  provider = aws.prod
  bucket   = aws_s3_bucket.canary_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# ATTACKER S3 BUCKET FOR EXPLOIT CODE
# =============================================================================

# Attacker-controlled bucket containing the malicious canary Python script
resource "aws_s3_bucket" "exploit_code" {
  provider = aws.attacker
  bucket   = "pl-synthetics-exploit-synthetics-001-${var.attacker_account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-synthetics-exploit-synthetics-001-${var.attacker_account_id}-${var.resource_suffix}"
    Environment = var.environment
    Scenario    = "iam-passrole+synthetics-createcanary+synthetics-startcanary"
    Purpose     = "exploit-code"
  }
}

# Block public access on the exploit code bucket
resource "aws_s3_bucket_public_access_block" "exploit_code" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.exploit_code.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Pre-stage the malicious canary script as a zip-compatible Python file
# The canary handler expects a Python module at python/<handler_file>.py
resource "aws_s3_object" "exploit_script" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.exploit_code.id
  key      = "canary-code/canary.zip"
  source   = "${path.module}/exploit_canary.zip"

  tags = {
    Name        = "exploit-canary-code"
    Environment = var.environment
    Scenario    = "iam-passrole+synthetics-createcanary+synthetics-startcanary"
    Purpose     = "attack-script"
  }
}

# Bucket policy granting read access to all principals in the prod account
# This simulates an attacker-controlled bucket that grants access to specific accounts
resource "aws_s3_bucket_policy" "exploit_code_policy" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.exploit_code.id

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
        Resource = "${aws_s3_bucket.exploit_code.arn}/*"
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
        Resource = aws_s3_bucket.exploit_code.arn
      }
    ]
  })
}

# =============================================================================
# STARTING USER POLICY
# =============================================================================

# Policy granting the starting user only the permissions required for exploitation
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-synthetics-001-to-admin-starting-user-policy"
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
        Sid    = "RequiredForExploitationSynthetics"
        Effect = "Allow"
        Action = [
          "synthetics:CreateCanary",
          "synthetics:StartCanary"
        ]
        Resource = "*"
      }
    ]
  })
}
