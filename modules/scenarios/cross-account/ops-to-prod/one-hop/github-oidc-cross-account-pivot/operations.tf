# GitHub OIDC Cross-Account Pivot - Operations Account Resources
#
# Creates the GitHub OIDC provider and an ops deployer role that GitHub Actions
# can assume via OIDC. The ops deployer role can then pivot cross-account into
# the prod deployer role.

# GitHub Actions OIDC provider in the operations account
resource "aws_iam_openid_connect_provider" "github" {
  provider        = aws.operations
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
  url             = "https://token.actions.githubusercontent.com"

  tags = {
    Name        = "pl-ops-goidc-pivot-github-oidc-provider"
    Environment = "operations"
    Scenario    = "github-oidc-cross-account-pivot"
    Purpose     = "github-oidc-provider"
  }
}

# Ops deployer role — trusted by GitHub Actions via OIDC for the configured repo.
# This is the initial foothold; it can only assume the specific prod deployer role.
resource "aws_iam_role" "ops_deployer" {
  force_detach_policies = true
  provider              = aws.operations
  name                  = "pl-ops-goidc-pivot-deployer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "pl-ops-goidc-pivot-deployer-role"
    Environment = "operations"
    Scenario    = "github-oidc-cross-account-pivot"
    Purpose     = "ops-deployer-oidc-entry"
  }
}

# Policy granting the ops deployer role the ability to assume ONLY the specific
# prod deployer role. The helpful permissions (sts:GetCallerIdentity, iam:ListRoles)
# make exploitation easier but are not strictly required to complete the attack.
resource "aws_iam_policy" "ops_deployer_policy" {
  provider    = aws.operations
  name        = "pl-ops-goidc-pivot-deployer-policy"
  description = "Allows the ops deployer role to pivot into the prod deployer role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationAssumeRole"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        # Scoped to the specific prod deployer role ARN — not a wildcard
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-goidc-pivot-deployer-role"
      },
      {
        Sid    = "HelpfulForExploitationDiscovery"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:ListRoles",
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ops_deployer_policy" {
  provider   = aws.operations
  role       = aws_iam_role.ops_deployer.name
  policy_arn = aws_iam_policy.ops_deployer_policy.arn
}
