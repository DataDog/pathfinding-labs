# Prod-account resources for the sts-role-chain cross-account scenario.
# No terraform block here — configuration_aliases is declared in dev.tf.

# Non-admin prod role that the dev role assumes as the second hop (cross-account).
# The trust policy explicitly names the per-scenario dev role, NOT the shared
# pl-pathfinding-starting-user-dev, to keep the scenario self-contained.
resource "aws_iam_role" "prod_non_admin_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-sts-role-chain-prod-non-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowDevRoleToAssumeFromDev"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.dev_account_id}:role/pl-dev-sts-role-chain-dev-role"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-sts-role-chain-prod-non-admin-role"
    Environment = "prod"
    Scenario    = "sts-role-chain"
    Purpose     = "prod-non-admin-hop-role"
  }
}

# Inline policy for the prod non-admin role: grants AssumeRole on the prod
# admin role (the final hop) plus helpful recon permissions.
resource "aws_iam_role_policy" "prod_non_admin_role" {
  provider = aws.prod
  name     = "pl-prod-sts-role-chain-prod-non-admin-role-policy"
  role     = aws_iam_role.prod_non_admin_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationAssumeRole"
        Effect = "Allow"
        Action = ["sts:AssumeRole"]
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-sts-role-chain-prod-admin-role"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:ListRoles",
        ]
        Resource = "*"
      }
    ]
  })
}

# Prod admin role — the final target. Trusted only by the prod non-admin role.
resource "aws_iam_role" "prod_admin_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-sts-role-chain-prod-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowProdNonAdminRoleToAssume"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-sts-role-chain-prod-non-admin-role"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-sts-role-chain-prod-admin-role"
    Environment = "prod"
    Scenario    = "sts-role-chain"
    Purpose     = "admin-target"
  }
}

# Attach AWS-managed AdministratorAccess to the prod admin role
resource "aws_iam_role_policy_attachment" "prod_admin_role" {
  provider   = aws.prod
  role       = aws_iam_role.prod_admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CTF flag stored in SSM Parameter Store. Retrieved by the attacker once they
# reach administrator-equivalent permissions via the full role chain.
# AdministratorAccess grants ssm:GetParameter implicitly, so no extra IAM
# wiring is needed.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/sts-role-chain-to-admin"
  description = "CTF flag for the sts-role-chain-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-sts-role-chain-flag"
    Environment = "prod"
    Scenario    = "sts-role-chain"
    Purpose     = "ctf-flag"
  }
}
