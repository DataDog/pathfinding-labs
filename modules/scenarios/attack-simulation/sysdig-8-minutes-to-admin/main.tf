# Sysdig "8 Minutes to Admin" attack simulation
#
# Recreation of the attack documented by Sysdig Threat Research Team documented at:
# https://www.sysdig.com/blog/ai-assisted-cloud-intrusion-achieves-admin-access-in-8-minutes
#
# Attack flow:
#   1. starting-user reads a private S3 RAG bucket, finds embedded credentials
#   2. compromised-user enumerates IAM, Lambda, Bedrock resources
#   3. compromised-user injects malicious code into the ec2-init Lambda
#   4. Lambda execution role (ec2-init-role) has iam:CreateAccessKey on frick (admin user)
#   5. Injected code calls iam:CreateAccessKey → attacker gets admin credentials
#   6. Further persistence: creates backdoor-admin with AdministratorAccess

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# =============================================================================
# LOCALS
# =============================================================================

locals {
  scenario_name   = "sysdig-8-minutes-to-admin"
  rag_bucket_name = "pl-prod-8min-rag-data-${var.account_id}-${var.resource_suffix}"
}

# =============================================================================
# LAMBDA FUNCTION CODE — packaged inline via archive_file
# =============================================================================

# Write the innocent-looking Lambda handler to a temp file for zipping
resource "local_file" "lambda_handler" {
  filename = "${path.module}/handler.py"
  content  = <<-PYTHON
import boto3
import json

def handler(event, context):
    """Initializes new EC2 instances by verifying connectivity and checking instance state."""
    ec2 = boto3.client('ec2')
    try:
        response = ec2.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['pending', 'running']}]
        )
        instance_count = sum(len(r['Instances']) for r in response['Reservations'])
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'EC2 init check complete. {instance_count} active instances.',
                'status': 'ok'
            })
        }
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
PYTHON
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_handler.filename
  output_path = "${path.module}/lambda_function.zip"
}

# =============================================================================
# IAM USER: starting-user
# =============================================================================

resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-8min-starting-user"

  tags = {
    Name        = "pl-prod-8min-starting-user"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "starting-user"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# starting-user can read the RAG bucket only — just enough to find the embedded credentials
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-8min-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationS3Read"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject"
        ]
        Resource = [
          "arn:aws:s3:::${local.rag_bucket_name}",
          "arn:aws:s3:::${local.rag_bucket_name}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# IAM USER: compromised-user (credentials embedded in S3 config file)
# =============================================================================

resource "aws_iam_user" "compromised_user" {
  provider = aws.prod
  name     = "pl-prod-8min-compromised-user"

  tags = {
    Name        = "pl-prod-8min-compromised-user"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "compromised-user"
    ManagedBy   = "pathfinding-labs"
  }
}

# Access keys are created so we can embed them in the S3 config file.
# They are NOT surfaced as direct Terraform outputs — discovery is via the bucket.
resource "aws_iam_access_key" "compromised_user_key" {
  provider = aws.prod
  user     = aws_iam_user.compromised_user.name
}

resource "aws_iam_user_policy" "compromised_user_policy" {
  provider = aws.prod
  name     = "pl-prod-8min-compromised-user-policy"
  user     = aws_iam_user.compromised_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Required: Lambda code injection into the ec2-init function
      {
        Sid    = "RequiredForExploitationLambdaInject"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:*:*:function:pl-prod-8min-ec2-init"
      },
      # Required: assume the three low-privilege roles for reconnaissance
      {
        Sid    = "RequiredForExploitationAssumeRoles"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          "arn:aws:iam::${var.account_id}:role/pl-prod-8min-sysadmin-role",
          "arn:aws:iam::${var.account_id}:role/pl-prod-8min-developer-role",
          "arn:aws:iam::${var.account_id}:role/pl-prod-8min-account-role"
        ]
      },
      # Helpful: IAM enumeration to identify frick (admin), ec2-init-role, etc.
      {
        Sid    = "HelpfulForExploitationIAMEnum"
        Effect = "Allow"
        Action = [
          "iam:ListUsers",
          "iam:ListRoles",
          "iam:GetUser",
          "iam:GetRole",
          "iam:ListAccessKeys",
          "iam:ListAttachedUserPolicies",
          "iam:ListGroupsForUser",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = "*"
      },
      # Helpful: Lambda discovery to find the ec2-init function and its execution role
      {
        Sid    = "HelpfulForExploitationLambdaEnum"
        Effect = "Allow"
        Action = [
          "lambda:ListFunctions",
          "lambda:GetFunction"
        ]
        Resource = "*"
      },
      # Helpful: Bedrock enumeration (attacker checks what models are available)
      {
        Sid    = "HelpfulForExploitationBedrockEnum"
        Effect = "Allow"
        Action = [
          "bedrock:ListFoundationModels",
          "bedrock:ListAgents",
          "bedrock:GetModelInvocationLoggingConfiguration",
          "bedrock:ListKnowledgeBases"
        ]
        Resource = "*"
      },
      # Helpful: S3, SSM, and Secrets Manager enumeration for data collection
      {
        Sid    = "HelpfulForExploitationDataEnum"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "ssm:DescribeParameters",
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      },
      # Helpful: verify current identity at each stage
      {
        Sid    = "HelpfulForExploitationIdentity"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# IAM USER: admingh (decoy — attacker tries to inject but fails)
# =============================================================================

resource "aws_iam_user" "admingh" {
  provider = aws.prod
  name     = "pl-prod-8min-admingh"

  tags = {
    Name        = "pl-prod-8min-admingh"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "decoy-failed-injection-target"
    ManagedBy   = "pathfinding-labs"
  }
}

# No policies — this user is a decoy that produces realistic access-denied errors
# during the demo's failed injection attempt steps.

# =============================================================================
# IAM USER: frick (admin target — access keys created at demo time via Lambda)
# =============================================================================

resource "aws_iam_user" "frick" {
  provider = aws.prod
  name     = "pl-prod-8min-frick"

  tags = {
    Name        = "pl-prod-8min-frick"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "admin-target"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_user_policy_attachment" "frick_admin_access" {
  provider   = aws.prod
  user       = aws_iam_user.frick.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# =============================================================================
# IAM USER: rocker (Bedrock-privileged user — for further persistence demo)
# =============================================================================

resource "aws_iam_user" "rocker" {
  provider = aws.prod
  name     = "pl-prod-8min-rocker"

  tags = {
    Name        = "pl-prod-8min-rocker"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "bedrock-persistence-target"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_user_policy_attachment" "rocker_bedrock_access" {
  provider   = aws.prod
  user       = aws_iam_user.rocker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}

# =============================================================================
# IAM USER: azureadmanager (Azure AD integration — pre-existing service account)
# =============================================================================

resource "aws_iam_user" "azureadmanager" {
  provider = aws.prod
  name     = "pl-prod-8min-azureadmanager"

  tags = {
    Name        = "pl-prod-8min-azureadmanager"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "azure-ad-integration"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_user_policy" "azureadmanager_policy" {
  provider = aws.prod
  name     = "pl-prod-8min-azureadmanager-policy"
  user     = aws_iam_user.azureadmanager.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AzureADSync"
      Effect = "Allow"
      Action = [
        "iam:ListUsers",
        "iam:ListRoles",
        "iam:GetUser",
        "iam:GetRole",
        "sts:GetCallerIdentity"
      ]
      Resource = "*"
    }]
  })
}

# =============================================================================
# IAM USER: deploy-svc (deployment service account — pre-existing)
# =============================================================================

resource "aws_iam_user" "deploy_svc" {
  provider = aws.prod
  name     = "pl-prod-8min-deploy-svc"

  tags = {
    Name        = "pl-prod-8min-deploy-svc"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "deployment-service"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_user_policy" "deploy_svc_policy" {
  provider = aws.prod
  name     = "pl-prod-8min-deploy-svc-policy"
  user     = aws_iam_user.deploy_svc.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DeploymentAccess"
      Effect = "Allow"
      Action = [
        "codedeploy:ListApplications",
        "codedeploy:GetDeployment",
        "s3:ListAllMyBuckets",
        "sts:GetCallerIdentity"
      ]
      Resource = "*"
    }]
  })
}

# =============================================================================
# IAM USER: monitoring (monitoring service account — pre-existing)
# =============================================================================

resource "aws_iam_user" "monitoring" {
  provider = aws.prod
  name     = "pl-prod-8min-monitoring"

  tags = {
    Name        = "pl-prod-8min-monitoring"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "monitoring-service"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_user_policy" "monitoring_policy" {
  provider = aws.prod
  name     = "pl-prod-8min-monitoring-policy"
  user     = aws_iam_user.monitoring.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "MonitoringAccess"
      Effect = "Allow"
      Action = [
        "cloudwatch:GetMetricData",
        "cloudwatch:ListMetrics",
        "logs:DescribeLogGroups",
        "sts:GetCallerIdentity"
      ]
      Resource = "*"
    }]
  })
}

# =============================================================================
# IAM USER: ci-runner (CI/CD runner service account — pre-existing)
# =============================================================================

resource "aws_iam_user" "ci_runner" {
  provider = aws.prod
  name     = "pl-prod-8min-ci-runner"

  tags = {
    Name        = "pl-prod-8min-ci-runner"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "ci-cd-runner"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_user_policy" "ci_runner_policy" {
  provider = aws.prod
  name     = "pl-prod-8min-ci-runner-policy"
  user     = aws_iam_user.ci_runner.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CIRunnerAccess"
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "codebuild:ListProjects",
        "sts:GetCallerIdentity"
      ]
      Resource = "*"
    }]
  })
}

# =============================================================================
# LOW-PRIVILEGE ROLES (assumed by compromised-user during recon, and by frick post-escalation)
# =============================================================================

resource "aws_iam_role" "sysadmin_role" {
  provider = aws.prod
  name     = "pl-prod-8min-sysadmin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-8min-sysadmin-role"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "low-priv-recon-role"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_role_policy" "sysadmin_role_policy" {
  provider = aws.prod
  name     = "pl-prod-8min-sysadmin-role-policy"
  role     = aws_iam_role.sysadmin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LowPrivRecon"
      Effect = "Allow"
      Action = [
        "sts:GetCallerIdentity",
        "ec2:DescribeInstances",
        "s3:ListAllMyBuckets"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "developer_role" {
  provider = aws.prod
  name     = "pl-prod-8min-developer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-8min-developer-role"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "low-priv-recon-role"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_role_policy" "developer_role_policy" {
  provider = aws.prod
  name     = "pl-prod-8min-developer-role-policy"
  role     = aws_iam_role.developer_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LowPrivRecon"
      Effect = "Allow"
      Action = [
        "sts:GetCallerIdentity",
        "ec2:DescribeInstances",
        "s3:ListAllMyBuckets"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "account_role" {
  provider = aws.prod
  name     = "pl-prod-8min-account-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-8min-account-role"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "low-priv-recon-role"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_role_policy" "account_role_policy" {
  provider = aws.prod
  name     = "pl-prod-8min-account-role-policy"
  role     = aws_iam_role.account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LowPrivRecon"
      Effect = "Allow"
      Action = [
        "sts:GetCallerIdentity",
        "ec2:DescribeInstances",
        "s3:ListAllMyBuckets"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "netadmin_role" {
  provider = aws.prod
  name     = "pl-prod-8min-netadmin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-8min-netadmin-role"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "low-priv-recon-role"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_role_policy" "netadmin_role_policy" {
  provider = aws.prod
  name     = "pl-prod-8min-netadmin-role-policy"
  role     = aws_iam_role.netadmin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LowPrivRecon"
      Effect = "Allow"
      Action = [
        "sts:GetCallerIdentity",
        "ec2:DescribeInstances",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "external_role" {
  provider = aws.prod
  name     = "pl-prod-8min-external-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-8min-external-role"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "low-priv-recon-role"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_role_policy" "external_role_policy" {
  provider = aws.prod
  name     = "pl-prod-8min-external-role-policy"
  role     = aws_iam_role.external_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LowPrivRecon"
      Effect = "Allow"
      Action = [
        "sts:GetCallerIdentity",
        "s3:ListAllMyBuckets"
      ]
      Resource = "*"
    }]
  })
}

# =============================================================================
# EC2-INIT LAMBDA EXECUTION ROLE (over-privileged — the key vulnerability)
# =============================================================================

resource "aws_iam_role" "ec2_init_role" {
  provider = aws.prod
  name     = "pl-prod-8min-ec2-init-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-8min-ec2-init-role"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "lambda-execution-role"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_iam_role_policy_attachment" "ec2_init_role_basic_execution" {
  provider   = aws.prod
  role       = aws_iam_role.ec2_init_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Over-privileged inline policy: legitimate EC2/S3 ops plus the exploitable iam:CreateAccessKey
resource "aws_iam_role_policy" "ec2_init_role_policy" {
  provider = aws.prod
  name     = "pl-prod-8min-ec2-init-role-policy"
  role     = aws_iam_role.ec2_init_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Legitimate-looking permissions for the original automation use case
      {
        Sid    = "LegitimateEC2Operations"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      # Required exploitation permission: create access keys on admin user frick
      # Also scoped to admingh so the demo failed-attempt produces a realistic error
      {
        Sid    = "RequiredForExploitationCreateAccessKey"
        Effect = "Allow"
        Action = [
          "iam:CreateAccessKey"
        ]
        Resource = [
          "arn:aws:iam::${var.account_id}:user/pl-prod-8min-frick",
          "arn:aws:iam::${var.account_id}:user/pl-prod-8min-admingh"
        ]
      },
      # Planned-but-unused automation features that were never removed
      {
        Sid    = "UnusedAutomationFeatures"
        Effect = "Allow"
        Action = [
          "iam:ListUsers",
          "iam:ListAccessKeys",
          "iam:ListAttachedUserPolicies",
          "iam:ListGroupsForUser",
          "s3:ListAllMyBuckets",
          "s3:ListObjectsV2"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# EC2-INIT LAMBDA FUNCTION
# =============================================================================

resource "aws_lambda_function" "ec2_init" {
  provider         = aws.prod
  function_name    = "pl-prod-8min-ec2-init"
  role             = aws_iam_role.ec2_init_role.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 3
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # depends_on ensures the role policy is attached before the function is created
  depends_on = [
    aws_iam_role_policy_attachment.ec2_init_role_basic_execution,
    aws_iam_role_policy.ec2_init_role_policy
  ]

  tags = {
    Name        = "pl-prod-8min-ec2-init"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "vulnerable-lambda"
    ManagedBy   = "pathfinding-labs"
  }
}

# =============================================================================
# PRIVATE S3 RAG BUCKET (contains embedded credentials in config file)
# =============================================================================

resource "aws_s3_bucket" "rag_data" {
  provider      = aws.prod
  bucket        = local.rag_bucket_name
  force_destroy = true

  tags = {
    Name        = local.rag_bucket_name
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "rag-data-bucket"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_s3_bucket_public_access_block" "rag_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.rag_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy: allow starting-user to list/read, deny everyone else
resource "aws_s3_bucket_policy" "rag_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.rag_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStartingUserAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.starting_user.arn
        }
        Action = [
          "s3:ListBucket",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.rag_data.arn,
          "${aws_s3_bucket.rag_data.arn}/*"
        ]
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.rag_data]
}

# Critical: RAG pipeline config with embedded credentials for compromised-user
# The attacker finds this file via s3:ListBucket + s3:GetObject
resource "aws_s3_object" "rag_pipeline_config" {
  provider     = aws.prod
  bucket       = aws_s3_bucket.rag_data.id
  key          = "config/rag-pipeline-config.json"
  content_type = "application/json"

  content = jsonencode({
    pipeline_name = "customer-data-rag"
    version       = "1.2.3"
    data_sources = [
      "s3://internal-data-lake/customer-records/",
      "s3://internal-data-lake/product-catalog/"
    ]
    embedding_model = "amazon.titan-embed-text-v1"
    vector_store = {
      type     = "opensearch"
      endpoint = "https://search.internal.example.com"
    }
    aws_credentials = {
      _comment          = "TODO: migrate to Secrets Manager before prod deployment"
      access_key_id     = aws_iam_access_key.compromised_user_key.id
      secret_access_key = aws_iam_access_key.compromised_user_key.secret
    }
    schedule = "0 2 * * *"
  })

  tags = {
    Scenario  = local.scenario_name
    ManagedBy = "pathfinding-labs"
  }
}

# Filler file: product FAQ (makes the bucket look like a real RAG data store)
resource "aws_s3_object" "product_faq" {
  provider     = aws.prod
  bucket       = aws_s3_bucket.rag_data.id
  key          = "data/knowledge-base/product-faq.txt"
  content_type = "text/plain"

  content = <<-EOT
Pathfinding Product FAQ - Internal Use Only

Q: What is the return policy?
A: Customers may return products within 30 days of purchase with a valid receipt.

Q: How do I reset my password?
A: Navigate to the login page and click "Forgot Password". You will receive an email with reset instructions.

Q: What payment methods are accepted?
A: We accept Visa, MasterCard, American Express, and PayPal.

Q: How long does shipping take?
A: Standard shipping takes 5-7 business days. Expedited shipping is available for an additional fee.

Q: Can I change my order after placing it?
A: Orders can be modified within 1 hour of placement. Contact support@internal.example.com for assistance.

Q: Is my data encrypted?
A: Yes, all customer data is encrypted at rest using AES-256 and in transit using TLS 1.3.
EOT

  tags = {
    Scenario  = local.scenario_name
    ManagedBy = "pathfinding-labs"
  }
}

# Filler file: embeddings readme
resource "aws_s3_object" "embeddings_readme" {
  provider     = aws.prod
  bucket       = aws_s3_bucket.rag_data.id
  key          = "data/embeddings/readme.md"
  content_type = "text/markdown"

  content = "Vector embeddings for customer data RAG pipeline"

  tags = {
    Scenario  = local.scenario_name
    ManagedBy = "pathfinding-labs"
  }
}

# Filler file: pipeline log
resource "aws_s3_object" "pipeline_log" {
  provider     = aws.prod
  bucket       = aws_s3_bucket.rag_data.id
  key          = "logs/pipeline-run-2025-11-27.log"
  content_type = "text/plain"

  content = <<-EOT
2025-11-27T02:00:01Z INFO  Pipeline started: customer-data-rag v1.2.3
2025-11-27T02:00:03Z INFO  Connecting to data sources...
2025-11-27T02:00:05Z INFO  Processing s3://internal-data-lake/customer-records/ (12847 documents)
2025-11-27T02:01:43Z INFO  Processing s3://internal-data-lake/product-catalog/ (3291 documents)
2025-11-27T02:02:11Z INFO  Generating embeddings via amazon.titan-embed-text-v1
2025-11-27T02:04:58Z INFO  Uploading vectors to OpenSearch endpoint
2025-11-27T02:05:32Z INFO  Index refresh complete. 16138 documents indexed.
2025-11-27T02:05:33Z INFO  Pipeline completed successfully. Duration: 5m32s
EOT

  tags = {
    Scenario  = local.scenario_name
    ManagedBy = "pathfinding-labs"
  }
}

# =============================================================================
# SECRETS MANAGER SECRET (recon target — attacker discovers this)
# =============================================================================

resource "aws_secretsmanager_secret" "db_credentials" {
  provider    = aws.prod
  name        = "pl-prod-8min-db-credentials-${var.resource_suffix}"
  description = "Production database credentials for customer data service"

  tags = {
    Name        = "pl-prod-8min-db-credentials-${var.resource_suffix}"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "recon-target"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  provider  = aws.prod
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = "prod_app_user"
    password = "Pr0d-DB-P@ssw0rd-2025!"
    host     = "prod-db.internal.example.com"
    port     = 5432
    database = "customer_data"
  })
}

# =============================================================================
# SSM PARAMETER (recon target — attacker discovers this)
# =============================================================================

# =============================================================================
# CTF FLAG (readable only with admin credentials)
# =============================================================================

resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/sysdig-8-minutes-to-admin-to-admin"
  type        = "String"
  value       = var.flag_value
  description = "CTF flag for the sysdig-8-minutes-to-admin scenario — readable only after achieving admin access via pl-prod-8min-frick"

  tags = {
    Name        = "pl-8min-ctf-flag"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "ctf-flag"
    ManagedBy   = "pathfinding-labs"
  }
}

resource "aws_ssm_parameter" "api_key" {
  provider    = aws.prod
  name        = "/pl/8min/api-key"
  type        = "SecureString"
  value       = "sk-prod-XkJ8mN2qP9vR4tY7wZ3aB6cE1fG5hI0jL"
  description = "Internal API key for data pipeline authentication"

  tags = {
    Name        = "pl-8min-api-key"
    Environment = var.environment
    Scenario    = local.scenario_name
    Purpose     = "recon-target"
    ManagedBy   = "pathfinding-labs"
  }
}
