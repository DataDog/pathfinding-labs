# GitHub OIDC Cross-Account Pivot - Prod Account Resources
#
# Creates the prod deployer role (trusted only by the specific ops deployer role ARN,
# not the :root principal), the flag S3 bucket, and its sensitive content.

# Prod deployer role — trusted by the ops deployer role ARN specifically.
# Using a specific ARN in the trust policy (not :root) is deliberate: it means
# only a principal that has already obtained credentials for the ops deployer role
# can assume this role. This models a tightly-scoped cross-account CI/CD trust.
resource "aws_iam_role" "prod_deployer" {
  provider = aws.prod
  name     = "pl-prod-goidc-pivot-deployer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.operations_account_id}:role/pl-ops-goidc-pivot-deployer-role"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-goidc-pivot-deployer-role"
    Environment = "prod"
    Scenario    = "github-oidc-cross-account-pivot"
    Purpose     = "prod-deployer-cross-account-target"
  }
}

# Inline policy for the prod deployer role.
#
# Story: This role is used by a GitHub Actions workflow to deploy/update an ECS
# service. The ECS and ECR permissions are the "legitimate" part — they're what
# the role was originally created for. The S3 permissions are the overprivileged
# part: someone added broad S3 access (maybe for deployment artifacts?) and it
# also covers the sensitive flag bucket. The attacker's job is to discover that
# this deployment role has more access than just ECS.
resource "aws_iam_role_policy" "prod_deployer_policy" {
  provider = aws.prod
  name     = "pl-prod-goidc-pivot-deployer-policy"
  role     = aws_iam_role.prod_deployer.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # --- Legitimate deployment permissions (the "intended" use) ---
      {
        Sid    = "ECSServiceDeployment"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:ListTasks"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRImagePull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "*"
      },
      {
        Sid    = "PassRoleToECSTask"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
      {
        Sid    = "DeploymentMonitoring"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      },
      # --- Overprivileged S3 access (the "oops" that makes the attack work) ---
      # Looks like someone added broad S3 read for deployment artifacts but
      # scoped it too wide — covers sensitive buckets too.
      {
        Sid    = "S3DeploymentArtifacts"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.flag_bucket.arn,
          "${aws_s3_bucket.flag_bucket.arn}/*"
        ]
      },
      {
        Sid    = "S3BucketDiscovery"
        Effect = "Allow"
        Action = ["s3:ListAllMyBuckets"]
        Resource = "*"
      }
    ]
  })
}

# Target S3 bucket containing sensitive data
resource "aws_s3_bucket" "flag_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-goidc-pivot-flag-${var.prod_account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-prod-goidc-pivot-flag-bucket"
    Environment = "prod"
    Scenario    = "github-oidc-cross-account-pivot"
    Purpose     = "target-bucket"
  }
}

# Block public access — this bucket is private and only accessible via the
# prod deployer role after the cross-account pivot succeeds
resource "aws_s3_bucket_public_access_block" "flag_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.flag_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sensitive file that confirms successful exploitation
resource "aws_s3_object" "sensitive_file" {
  provider = aws.prod
  bucket   = aws_s3_bucket.flag_bucket.id
  key      = "sensitive-data.txt"
  content  = "SUCCESS! GitHub Actions OIDC cross-account pivot complete.\nFlag: PATHFINDER-GITHUB-OIDC-CROSS-ACCOUNT-2024"
}
