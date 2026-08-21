terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# AgentCore Runtime Command Injection privilege escalation scenario (bedrock-004)
#
# This scenario demonstrates how a principal with only
# bedrock-agentcore:InvokeAgentRuntimeCommand can exploit an EXISTING AgentCore
# Runtime that was deployed by the victim account with an admin execution role.
#
# Unlike bedrock-003 (where the attacker creates a new runtime with PassRole),
# here the attacker has no PassRole and cannot create runtimes. The victim's
# infrastructure is already misconfigured: a running AgentCore Runtime holds an
# execution role with AdministratorAccess. The attacker needs only one action —
# InvokeAgentRuntimeCommand — to run arbitrary commands inside the runtime
# microVM and read temporary credentials from MMDS at 169.254.169.254.
#
# Attack path:
#   starting_user
#     → bedrock-agentcore:InvokeAgentRuntimeCommand
#     → victim's existing Runtime (admin execution role attached)
#     → run: curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
#     → extract AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
#     → admin access → ssm:GetParameter → CTF flag
#
# Resource naming convention: pl-prod-bedrock-004-to-admin-{resource-type}
# Provider: aws.prod only (victim ECR + Runtime — no attacker account needed)

locals {
  # ECR repo lives in the prod (victim) account; underscores required in ECR names.
  ecr_repo_name = "pl_prod_bedrock_004_to_admin_runtime"
  ecr_image_uri = "${var.account_id}.dkr.ecr.${data.aws_region.prod.name}.amazonaws.com/${local.ecr_repo_name}:latest"

  # AgentCore Runtime name — underscores required by the AgentCore API.
  runtime_name = "pl_prod_bedrock_004_to_admin_target_runtime"

  # SSM path used to persist the runtime ARN across plan/apply invocations so
  # the demo script can read it without shelling out to the AWS CLI separately.
  runtime_arn_ssm_path = "/pathfinding-labs/bedrock-004/runtime-arn"
}

# Look up the prod region so we can construct the ECR image URI deterministically.
data "aws_region" "prod" {
  provider = aws.prod
}

# ---------------------------------------------------------------------------
# Scenario-specific starting user
# ---------------------------------------------------------------------------

# force_destroy = true lets Terraform clean up any policies, access keys,
# login profiles, or group memberships the demo attaches out-of-band so
# destroy still succeeds if the user disables the scenario without first
# running cleanup_attack.sh.
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-bedrock-004-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-bedrock-004-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "bedrockagentcore-invokeagentcommand"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# The starting user has the single required action plus recon helpers.
# InvokeAgentRuntimeCommand is left at resource = "*" because the runtime ARN
# is not known until the null_resource creates it at apply time, and scoping
# the policy to a wildcard is realistic — the victim account's runtime is what
# exists and what the attacker discovers via ListAgentRuntimes.
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-bedrock-004-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationBedrockAgentCore"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:InvokeAgentRuntimeCommand"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:ListAgentRuntimes",
          "bedrock-agentcore:GetAgentRuntime"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Target admin role (victim's execution role — pre-existing misconfiguration)
# ---------------------------------------------------------------------------

# force_detach_policies = true ensures destroy succeeds even if the demo
# attaches additional managed policies out-of-band.
resource "aws_iam_role" "target_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-bedrock-004-to-admin-target-role"

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
    Name        = "pl-prod-bedrock-004-to-admin-target-role"
    Environment = var.environment
    Scenario    = "bedrockagentcore-invokeagentcommand"
    Purpose     = "admin-target"
  }
}

resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# The target role also needs ECR pull permissions so the AgentCore service can
# pull the container image from the victim ECR repo when it starts the runtime.
resource "aws_iam_role_policy" "target_role_ecr_pull" {
  provider = aws.prod
  name     = "pl-prod-bedrock-004-to-admin-target-role-ecr-pull"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# CTF flag stored in SSM Parameter Store
# ---------------------------------------------------------------------------

# Retrieved by the attacker once they reach administrator-equivalent permissions
# via the extracted MMDS credentials. AdministratorAccess grants ssm:GetParameter
# implicitly — no extra IAM wiring needed.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/bedrock-004-to-admin"
  description = "CTF flag for the bedrock-004-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-bedrock-004-to-admin-flag"
    Environment = var.environment
    Scenario    = "bedrockagentcore-invokeagentcommand"
    Purpose     = "ctf-flag"
  }
}

# ---------------------------------------------------------------------------
# Victim ECR repository (prod account — victim deployed their own runtime)
# ---------------------------------------------------------------------------

# The victim account hosts its own ECR repo and container image. This is the
# realistic misconfiguration: the victim organisation built and operates an
# AgentCore Runtime without restricting who can invoke it.
resource "aws_ecr_repository" "runtime_image" {
  provider             = aws.prod
  name                 = local.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name        = "pl-prod-bedrock-004-to-admin-runtime"
    Environment = var.environment
    Scenario    = "bedrockagentcore-invokeagentcommand"
    Purpose     = "victim-ecr-repo"
  }
}

# Build and push the container image to the victim (prod) ECR repo.
# Uses docker buildx to produce a linux/arm64 image because AgentCore Runtime
# runs on Graviton. The null_resource re-runs whenever the Dockerfile or
# server.py changes (tracked via content hashes).
# Note: null_resource uses the null provider — no provider = aws.prod here.
resource "null_resource" "build_and_push_image" {
  depends_on = [
    aws_ecr_repository.runtime_image
  ]

  triggers = {
    dockerfile_hash = filemd5("${path.module}/container/Dockerfile")
    server_hash     = filemd5("${path.module}/container/server.py")
    ecr_repo_url    = aws_ecr_repository.runtime_image.repository_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail

      REPO_URL="${aws_ecr_repository.runtime_image.repository_url}"
      REGION="${data.aws_region.prod.name}"
      ACCOUNT="${var.account_id}"

      PROFILE="${var.prod_account_aws_profile}"
      echo "Authenticating to ECR in prod account $ACCOUNT ($REGION) using profile $PROFILE..."
      if [ -n "$PROFILE" ]; then
        aws ecr get-login-password --region "$REGION" --profile "$PROFILE" \
        | docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
      else
        aws ecr get-login-password --region "$REGION" \
        | docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
      fi

      echo "Building linux/arm64 image and pushing to $REPO_URL:latest..."
      docker buildx build \
        --platform linux/arm64 \
        --provenance=false \
        --push \
        --tag "$REPO_URL:latest" \
        "${path.module}/container"

      echo "Image pushed successfully."
    EOT

    interpreter = ["/bin/bash", "-c"]
  }
}

# ---------------------------------------------------------------------------
# Victim AgentCore Runtime (pre-existing misconfigured infrastructure)
# ---------------------------------------------------------------------------

# aws_bedrockagentcore_agent_runtime is not yet available in the AWS Terraform
# provider 6.x as of this writing. We use a null_resource + AWS CLI to create
# and destroy the Runtime imperatively.
#
# The runtime ARN is persisted in SSM so that the demo script and outputs can
# reference it without running a separate AWS CLI call.
#
# The Runtime uses:
#   - networkMode PUBLIC   (required so InvokeAgentRuntimeCommand can reach it)
#   - inboundAuthType IAM  (default; allows any principal with the IAM action)
#   - executionRoleArn     = target_role (AdministratorAccess)
#   - containerImage       = victim ECR image
resource "null_resource" "agentcore_runtime" {
  depends_on = [
    aws_iam_role_policy_attachment.target_role_admin_access,
    aws_iam_role_policy.target_role_ecr_pull,
    null_resource.build_and_push_image
  ]

  triggers = {
    # Recreate the runtime if the execution role or image changes.
    target_role_arn = aws_iam_role.target_role.arn
    ecr_image_uri   = local.ecr_image_uri
    runtime_name    = local.runtime_name
    region          = data.aws_region.prod.name
    account_id      = var.account_id
    profile         = var.prod_account_aws_profile
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail

      REGION="${data.aws_region.prod.name}"
      ROLE_ARN="${aws_iam_role.target_role.arn}"
      IMAGE_URI="${local.ecr_image_uri}"
      RUNTIME_NAME="${local.runtime_name}"
      SSM_PATH="${local.runtime_arn_ssm_path}"
      PROFILE="${var.prod_account_aws_profile}"
      if [ -n "$PROFILE" ]; then export AWS_PROFILE="$PROFILE"; fi

      # Idempotent: if a runtime with this name already exists (e.g. left
      # over from a prior apply whose local-exec failed after creation but
      # before the SSM write below), reuse it instead of failing with
      # ConflictException.
      EXISTING_ARN=$(aws bedrock-agentcore-control list-agent-runtimes \
        --region "$REGION" \
        --query "agentRuntimes[?agentRuntimeName=='$RUNTIME_NAME'].agentRuntimeArn | [0]" \
        --output text 2>/dev/null || echo "None")

      if [ -n "$EXISTING_ARN" ] && [ "$EXISTING_ARN" != "None" ]; then
        echo "Runtime '$RUNTIME_NAME' already exists — reusing it."
        RUNTIME_ARN="$EXISTING_ARN"
      else
        echo "Creating AgentCore Runtime '$RUNTIME_NAME' in region $REGION..."
        RUNTIME_ARN=$(aws bedrock-agentcore-control create-agent-runtime \
          --region "$REGION" \
          --agent-runtime-name "$RUNTIME_NAME" \
          --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"$IMAGE_URI\"}}" \
          --role-arn "$ROLE_ARN" \
          --network-configuration "{\"networkMode\":\"PUBLIC\"}" \
          --query 'agentRuntimeArn' \
          --output text)
      fi

      echo "Runtime ARN: $RUNTIME_ARN"

      # Persist the ARN before polling for READY: if the poll below hits the
      # FAILED branch (or anything else kills this script), the destroy
      # provisioner can still find and clean up this resource on the next
      # apply instead of leaving an orphan that blocks recreation.
      echo "Storing runtime ARN in SSM at $SSM_PATH..."
      aws ssm put-parameter \
        --region "$REGION" \
        --name "$SSM_PATH" \
        --value "$RUNTIME_ARN" \
        --type "String" \
        --overwrite

      echo "Waiting for Runtime to reach READY state (may take several minutes)..."
      for i in $(seq 1 40); do
        STATUS=$(aws bedrock-agentcore-control get-agent-runtime \
          --region "$REGION" \
          --agent-runtime-id "$RUNTIME_ARN" \
          --query 'status' \
          --output text 2>/dev/null || echo "UNKNOWN")
        echo "  Status: $STATUS (attempt $i/40)"
        if [ "$STATUS" = "READY" ]; then
          echo "Runtime is READY."
          break
        elif [ "$STATUS" = "FAILED" ]; then
          echo "ERROR: Runtime creation FAILED." >&2
          exit 1
        fi
        sleep 15
      done

      echo "AgentCore Runtime created and READY."
    EOT

    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    when = destroy

    command = <<-EOT
      set -euo pipefail

      REGION="${self.triggers.region}"
      SSM_PATH="/pathfinding-labs/bedrock-004/runtime-arn"
      PROFILE="${self.triggers.profile}"
      if [ -n "$PROFILE" ]; then export AWS_PROFILE="$PROFILE"; fi

      echo "Retrieving runtime ARN from SSM for deletion..."
      RUNTIME_ARN=$(aws ssm get-parameter \
        --region "$REGION" \
        --name "$SSM_PATH" \
        --query 'Parameter.Value' \
        --output text 2>/dev/null || echo "")

      if [ -z "$RUNTIME_ARN" ]; then
        echo "No runtime ARN found in SSM — skipping runtime deletion."
      else
        echo "Deleting AgentCore Runtime: $RUNTIME_ARN"
        aws bedrock-agentcore-control delete-agent-runtime \
          --region "$REGION" \
          --agent-runtime-id "$RUNTIME_ARN" \
          || echo "WARNING: Runtime deletion failed or already deleted."

        echo "Removing SSM parameter $SSM_PATH..."
        aws ssm delete-parameter \
          --region "$REGION" \
          --name "$SSM_PATH" \
          || echo "WARNING: SSM parameter deletion failed."
      fi

      echo "AgentCore Runtime teardown complete."
    EOT

    interpreter = ["/bin/bash", "-c"]
  }
}

# SSM parameter that stores the runtime ARN so Terraform outputs and the demo
# script can reference it without re-running the AWS CLI. Written by the
# null_resource above; read back here as a data source after creation.
data "aws_ssm_parameter" "runtime_arn" {
  provider = aws.prod
  name     = local.runtime_arn_ssm_path

  depends_on = [null_resource.agentcore_runtime]
}
