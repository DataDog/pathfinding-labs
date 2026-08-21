terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod, aws.attacker]
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# AgentCore Runtime Creation privilege escalation scenario (bedrock-003)
#
# This scenario demonstrates how a principal with iam:PassRole and AgentCore Runtime
# create/invoke permissions can deploy a new Runtime with a privileged execution role,
# then extract temporary credentials from the MicroVM Metadata Service (MMDS) at
# 169.254.169.254 to gain admin access.
#
# Attack path:
#   starting_user
#     → (iam:PassRole + CreateAgentRuntime + CreateAgentRuntimeEndpoint
#          + CreateWorkloadIdentity + InvokeAgentRuntimeCommand)
#     → new Runtime running attacker's container image with admin execution role
#     → InvokeAgentRuntimeCommand runs arbitrary code as the runtime
#     → extract credentials from MMDS at 169.254.169.254
#     → admin access → ssm:GetParameter → CTF flag
#
# Resource naming convention: pl-prod-bedrock-003-to-admin-{resource-type}
# Provider: aws.prod for victim resources, aws.attacker for attacker-controlled ECR

locals {
  ecr_image_uri = "${var.attacker_account_id}.dkr.ecr.${data.aws_region.attacker.name}.amazonaws.com/pl-prod-bedrock-003-to-admin-runtime:latest"
}

# Derive the attacker account's region for ECR URI construction
data "aws_region" "attacker" {
  provider = aws.attacker
}

# ---------------------------------------------------------------------------
# Victim-side resources (aws.prod)
# ---------------------------------------------------------------------------

# Scenario-specific starting user
# force_destroy = true lets Terraform clean up any policies, access keys,
# login profiles, or group memberships the demo attaches out-of-band so
# destroy still succeeds if the user disables the scenario without first
# running cleanup_attack.sh.
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-bedrock-003-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-bedrock-003-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-createagentruntime"
    Purpose     = "starting-user"
  }
}

# Access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# IAM policy granting the exact permissions required to exploit the scenario.
# The PassRole permission is scoped to the target role with a service condition
# so that Terraform itself cannot accidentally escalate; only the
# bedrock-agentcore service can receive the role.
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-bedrock-003-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = aws_iam_role.target_role.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "bedrock-agentcore.amazonaws.com"
          }
        }
      },
      {
        Sid    = "RequiredForExploitationBedrockAgentCore"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:CreateAgentRuntime",
          "bedrock-agentcore:CreateAgentRuntimeEndpoint",
          "bedrock-agentcore:CreateWorkloadIdentity",
          "bedrock-agentcore:InvokeAgentRuntimeCommand"
        ]
        Resource = "*"
      },
      {
        # TEMPORARY: allows the service to auto-create its SLRs on first use in a fresh account.
        # Once we identify all SLRs from a successful run they will be pre-created in
        # modules/environments/prod and this statement will be removed.
        Sid    = "TemporaryAllowSLRCreationForBootstrap"
        Effect = "Allow"
        Action = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole",
          "bedrock-agentcore:GetAgentRuntime"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target role with AdministratorAccess — passed to the new Runtime as its
# execution role. The bedrock-agentcore service principal must be trusted so
# the service can assume the role when the runtime starts.
# force_detach_policies = true ensures destroy succeeds even if the demo
# attaches additional managed policies out-of-band.
resource "aws_iam_role" "target_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-bedrock-003-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBedrockAgentCoreService"
        Effect = "Allow"
        Principal = {
          Service = "bedrock-agentcore.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-bedrock-003-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-createagentruntime"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the target role so any code running inside
# the runtime has full AWS permissions in the victim account.
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CTF flag stored in SSM Parameter Store. Retrieved by the attacker once they
# reach administrator-equivalent permissions (AdministratorAccess grants
# ssm:GetParameter implicitly, so no extra IAM wiring is needed).
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/bedrock-003-to-admin"
  description = "CTF flag for the bedrock-003-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-bedrock-003-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-createagentruntime"
    Purpose     = "ctf-flag"
  }
}

# ---------------------------------------------------------------------------
# Attacker-side resources (aws.attacker)
# ---------------------------------------------------------------------------

# ECR repository in the attacker account that hosts the container image
# required by AgentCore Runtime. The runtime will pull from this repo using
# the execution role's credentials.
resource "aws_ecr_repository" "runtime_image" {
  provider             = aws.attacker
  name                 = "pl-prod-bedrock-003-to-admin-runtime"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name        = "pl-prod-bedrock-003-to-admin-runtime"
    Environment = var.environment
    Scenario    = "iam-passrole+bedrockagentcore-createagentruntime"
    Purpose     = "attacker-ecr-repo"
  }
}

# ECR repository policy granting the victim (prod) account permission to pull
# the image. AgentCore Runtime pulls the image using the execution role's
# credentials, which live in the prod account.
resource "aws_ecr_repository_policy" "runtime_image_policy" {
  provider   = aws.attacker
  repository = aws_ecr_repository.runtime_image.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowProdAccountPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# The attacker container image is built and pushed by demo_attack.sh at demo time,
# not at Terraform apply time. This keeps infra provisioning (Terraform) separate
# from attacker tooling (demo script), and avoids requiring Docker at apply time.
# demo_attack.sh authenticates to ECR using the attacker profile and builds the
# linux/arm64 image before calling CreateAgentRuntime.
