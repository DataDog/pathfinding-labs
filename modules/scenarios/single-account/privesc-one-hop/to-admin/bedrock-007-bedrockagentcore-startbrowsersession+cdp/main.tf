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

# AgentCore Custom Browser CDP Credential Theft privilege escalation scenario (bedrock-007)
#
# This scenario demonstrates how a principal with only
# bedrock-agentcore:StartBrowserSession and bedrock-agentcore:ConnectBrowserAutomationStream
# can exploit an EXISTING Custom Browser that the victim provisioned with an admin
# execution role.
#
# Unlike bedrock-003/bedrock-006 (where the attacker uses iam:PassRole to create a new
# browser/runtime with a privileged role), here the attacker has no PassRole and cannot
# create browsers. The victim's infrastructure is already misconfigured: an existing
# AgentCore Custom Browser holds an execution role with AdministratorAccess. The
# attacker needs only two actions to open a browser automation session and drive the
# Chromium instance over the Chrome DevTools Protocol (CDP).
#
# Attack path:
#   starting_user
#     → bedrock-agentcore:StartBrowserSession on existing Custom Browser (admin execution role attached)
#     → bedrock-agentcore:ConnectBrowserAutomationStream  (opens CDP WebSocket)
#     → Playwright/CDP context.route() hook intercepts MMDS token request
#     → rewrite request to read execution role credentials at 169.254.169.254
#     → extract AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
#     → admin access → ssm:GetParameter → CTF flag
#
# Resource naming convention: pl-prod-bedrock-007-to-admin-{resource-type}
# Provider: aws.prod only

locals {
  # Custom Browser name — underscores required by the AgentCore API.
  browser_name = "pl_prod_bedrock_007_to_admin_victim_browser"

  # SSM path used to persist the browser ID across plan/apply invocations so
  # the demo script can read it without shelling out to the AWS CLI separately.
  browser_id_ssm_path = "/pathfinding-labs/bedrock-007/browser-id"
}

# Look up the prod region so we can construct ARNs and CLI commands deterministically.
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
  name          = "pl-prod-bedrock-007-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-bedrock-007-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "bedrockagentcore-startbrowsersession+cdp"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# The starting user has the two required actions plus recon helpers.
# Both actions are left at resource = "*" because the browser ID is not known
# until the null_resource creates it at apply time, and wildcard is realistic —
# the attacker discovers the victim's browser via ListBrowsers.
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-bedrock-007-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationBrowserCDP"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:StartBrowserSession",
          "bedrock-agentcore:ConnectBrowserAutomationStream"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:ListBrowsers",
          "bedrock-agentcore:GetBrowser"
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
  name                  = "pl-prod-bedrock-007-to-admin-target-role"

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
    Name        = "pl-prod-bedrock-007-to-admin-target-role"
    Environment = var.environment
    Scenario    = "bedrockagentcore-startbrowsersession+cdp"
    Purpose     = "admin-target"
  }
}

resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# The target role also needs ECR pull permissions so the AgentCore service can
# pull the Chromium container image when it starts the browser session.
resource "aws_iam_role_policy" "target_role_ecr_pull" {
  provider = aws.prod
  name     = "pl-prod-bedrock-007-to-admin-target-role-ecr-pull"
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
  name        = "/pathfinding-labs/flags/bedrock-007-to-admin"
  description = "CTF flag for the bedrock-007-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-bedrock-007-to-admin-flag"
    Environment = var.environment
    Scenario    = "bedrockagentcore-startbrowsersession+cdp"
    Purpose     = "ctf-flag"
  }
}

# ---------------------------------------------------------------------------
# Victim AgentCore Custom Browser (pre-existing misconfigured infrastructure)
# ---------------------------------------------------------------------------

# aws_bedrockagentcore_browser is not available in the AWS Terraform provider 6.x
# as of this writing. We use a null_resource + AWS CLI to create and destroy the
# Custom Browser imperatively.
#
# The browser ID is persisted in SSM so that the demo script and outputs can
# reference it without running a separate AWS CLI call.
#
# The Custom Browser uses AWS-managed Chromium — no container image is needed.
# The executionRoleArn is what makes this browser vulnerable: any principal with
# StartBrowserSession + ConnectBrowserAutomationStream can open a CDP session and
# read the role's temporary credentials from MMDS.
resource "null_resource" "agentcore_browser" {
  depends_on = [
    aws_iam_role_policy_attachment.target_role_admin_access,
    aws_iam_role_policy.target_role_ecr_pull
  ]

  triggers = {
    # Recreate the browser if the execution role or name changes.
    target_role_arn = aws_iam_role.target_role.arn
    browser_name    = local.browser_name
    region          = data.aws_region.prod.name
    account_id      = var.account_id
    profile         = var.prod_account_aws_profile
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail

      REGION="${data.aws_region.prod.name}"
      ROLE_ARN="${aws_iam_role.target_role.arn}"
      BROWSER_NAME="${local.browser_name}"
      SSM_PATH="${local.browser_id_ssm_path}"
      PROFILE="${var.prod_account_aws_profile}"
      if [ -n "$PROFILE" ]; then export AWS_PROFILE="$PROFILE"; fi

      # Idempotent: if a browser with this name already exists (e.g. left
      # over from a prior apply whose local-exec failed after creation but
      # before the SSM write below), reuse it instead of failing with
      # ConflictException.
      EXISTING_ID=$(aws bedrock-agentcore-control list-browsers \
        --region "$REGION" \
        --query "browserSummaries[?name=='$BROWSER_NAME'].browserId | [0]" \
        --output text 2>/dev/null || echo "None")

      if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "None" ]; then
        echo "Browser '$BROWSER_NAME' already exists — reusing it."
        BROWSER_ID="$EXISTING_ID"
      else
        echo "Creating AgentCore Custom Browser '$BROWSER_NAME' in region $REGION..."
        BROWSER_ID=$(aws bedrock-agentcore-control create-browser \
          --region "$REGION" \
          --name "$BROWSER_NAME" \
          --execution-role-arn "$ROLE_ARN" \
          --network-configuration '{"networkMode":"PUBLIC"}' \
          --query 'browserId' \
          --output text)
      fi

      echo "Browser ID: $BROWSER_ID"

      # Persist the ID before polling for READY: if the poll below hits the
      # FAILED branch (or anything else kills this script), the destroy
      # provisioner can still find and clean up this resource on the next
      # apply instead of leaving an orphan that blocks recreation.
      echo "Storing browser ID in SSM at $SSM_PATH..."
      aws ssm put-parameter \
        --region "$REGION" \
        --name "$SSM_PATH" \
        --value "$BROWSER_ID" \
        --type "String" \
        --overwrite

      echo "Waiting for Browser to reach READY state (may take several minutes)..."
      for i in $(seq 1 40); do
        STATUS=$(aws bedrock-agentcore-control get-browser \
          --region "$REGION" \
          --browser-id "$BROWSER_ID" \
          --query 'status' \
          --output text 2>/dev/null || echo "UNKNOWN")
        echo "  Status: $STATUS (attempt $i/40)"
        if [ "$STATUS" = "READY" ]; then
          echo "Browser is READY."
          break
        elif [ "$STATUS" = "FAILED" ]; then
          echo "ERROR: Browser creation FAILED." >&2
          exit 1
        fi
        sleep 15
      done

      echo "AgentCore Custom Browser created and READY."
    EOT

    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    when = destroy

    command = <<-EOT
      set -euo pipefail

      REGION="${self.triggers.region}"
      SSM_PATH="/pathfinding-labs/bedrock-007/browser-id"
      PROFILE="${self.triggers.profile}"
      if [ -n "$PROFILE" ]; then export AWS_PROFILE="$PROFILE"; fi

      echo "Retrieving browser ID from SSM for deletion..."
      BROWSER_ID=$(aws ssm get-parameter \
        --region "$REGION" \
        --name "$SSM_PATH" \
        --query 'Parameter.Value' \
        --output text 2>/dev/null || echo "")

      if [ -z "$BROWSER_ID" ]; then
        echo "No browser ID found in SSM — skipping browser deletion."
      else
        echo "Deleting AgentCore Custom Browser: $BROWSER_ID"
        aws bedrock-agentcore-control delete-browser \
          --region "$REGION" \
          --browser-id "$BROWSER_ID" \
          || echo "WARNING: Browser deletion failed or already deleted."

        echo "Removing SSM parameter $SSM_PATH..."
        aws ssm delete-parameter \
          --region "$REGION" \
          --name "$SSM_PATH" \
          || echo "WARNING: SSM parameter deletion failed."
      fi

      echo "AgentCore Custom Browser teardown complete."
    EOT

    interpreter = ["/bin/bash", "-c"]
  }
}

# Read back the browser ID that the null_resource provisioner wrote to SSM.
# Using a data source (not a resource) because the null_resource already owns
# the lifecycle of this parameter — its destroy provisioner deletes it. A
# resource would conflict with the null_resource's put-parameter call on first
# apply and cause ParameterAlreadyExists.
data "aws_ssm_parameter" "victim_browser_id" {
  provider = aws.prod
  name     = local.browser_id_ssm_path

  depends_on = [null_resource.agentcore_browser]
}
