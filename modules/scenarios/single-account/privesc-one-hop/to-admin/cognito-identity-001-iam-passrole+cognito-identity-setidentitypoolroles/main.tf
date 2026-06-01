terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + cognito-identity:SetIdentityPoolRoles privilege escalation scenario
#
# This scenario demonstrates how an attacker with iam:PassRole and
# cognito-identity:SetIdentityPoolRoles can bind an admin-equivalent IAM role to
# an existing Cognito Identity Pool's unauthenticated slot. Once bound, anyone
# (including a fully public, unauthenticated caller) can call GetId,
# GetOpenIdToken, and then sts:AssumeRoleWithWebIdentity to obtain temporary
# credentials for the admin role — no Cognito user pool, no login, no MFA.
#
# The classic flow (allow_classic_flow = true) is essential: the enhanced flow
# (GetCredentialsForIdentity) attaches a Cognito-managed session policy that
# blocks most IAM and SSM actions, so the role's AdministratorAccess would be
# effectively neutered. The classic flow skips that policy, giving unconstrained
# access.
#
# Resource naming convention: pl-prod-cognito-identity-001-to-admin-{resource-type}
# Provider: aws.prod (single-account scenario)

# ── Prerequisite: Cognito Identity Pool ───────────────────────────────────────
# Models a mobile app's guest-access tier. Starts with no unauthenticated role
# configured. The attacker is the one who binds the admin role.
resource "aws_cognito_identity_pool" "pool" {
  provider                         = aws.prod
  identity_pool_name               = "pl-prod-cognito-identity-001-to-admin-pool"
  allow_unauthenticated_identities = true
  # Classic flow required: GetCredentialsForIdentity (enhanced flow) attaches a
  # Cognito-managed session policy that blocks ssm:* and most IAM actions.
  # The classic flow (GetOpenIdToken → sts:AssumeRoleWithWebIdentity) does not
  # attach a session policy, so AdministratorAccess applies without restriction.
  allow_classic_flow               = true

  tags = {
    Name        = "pl-prod-cognito-identity-001-to-admin-pool"
    Environment = var.environment
    Scenario    = "cognito-identity-001-iam-passrole+cognito-identity-setidentitypoolroles"
    Purpose     = "victim-identity-pool"
  }
}

# ── Prerequisite: Admin role trusted by the Cognito pool ──────────────────────
# Trust policy scopes trust to the specific pool (IAM rejects wildcards in the
# aud condition for Cognito federated principals). The ForAnyValue:StringLike
# condition limits assumption to the unauthenticated flow.
resource "aws_iam_role" "admin_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-cognito-identity-001-to-admin-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCognitoUnauthenticatedAssumption"
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.pool.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "unauthenticated"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "pl-prod-cognito-identity-001-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "cognito-identity-001-iam-passrole+cognito-identity-setidentitypoolroles"
    Purpose     = "admin-target"
  }
}

resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ── Starting principal (attacker) ─────────────────────────────────────────────
# force_destroy = true lets Terraform clean up any policies, access keys,
# login profiles, or group memberships the demo attaches out-of-band, so
# destroy succeeds if the user disables the scenario without first running
# cleanup_attack.sh.
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-cognito-identity-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-cognito-identity-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "cognito-identity-001-iam-passrole+cognito-identity-setidentitypoolroles"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-cognito-identity-001-to-admin-starting-user-policy"
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
        # Scoped to the specific admin role — PassRole on * would be much broader
        # than what the scenario requires and would widen the blast radius.
        Resource = aws_iam_role.admin_role.arn
      },
      {
        Sid    = "RequiredForExploitationSetIdentityPoolRoles"
        Effect = "Allow"
        Action = [
          "cognito-identity:SetIdentityPoolRoles"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "cognito-identity:ListIdentityPools",
          "cognito-identity:DescribeIdentityPool",
          "cognito-identity:GetIdentityPoolRoles",
          "iam:ListRoles",
          "iam:GetRole"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── CTF flag ──────────────────────────────────────────────────────────────────
# Stored in SSM Parameter Store. The attacker retrieves this after assuming the
# admin role (AdministratorAccess grants ssm:GetParameter implicitly — no extra
# IAM wiring is needed).
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/cognito-identity-001-to-admin"
  description = "CTF flag for the cognito-identity-001-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-cognito-identity-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "cognito-identity-001-iam-passrole+cognito-identity-setidentitypoolroles"
    Purpose     = "ctf-flag"
  }
}
