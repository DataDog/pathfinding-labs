# PassRole + Amplify CreateApp + CreateBranch + StartJob privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, amplify:CreateApp,
# amplify:CreateBranch, and amplify:StartJob can escalate privileges by:
# 1. Creating a CodeCommit repository with a malicious amplify.yml build spec
# 2. Creating an Amplify app connected to the repo, passing an admin service role via iam:PassRole
# 3. Creating a branch and starting a build job
# 4. The Amplify build environment executes with the admin role's credentials
# 5. Build commands attach AdministratorAccess to the starting user
#
# Cost: $0/mo at rest (IAM + CodeCommit repo only, no compute until build runs)

# Resource naming convention: pl-prod-amplify-001-to-admin-{resource-type}
# amplify-001 = pathfinding.cloud ID for this scenario

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
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-amplify-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-amplify-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+amplify-createapp+amplify-createbranch+amplify-startjob"
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
  name     = "pl-prod-amplify-001-to-admin-required-permissions"
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
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "amplify.amazonaws.com"
          }
        }
      },
      {
        Sid    = "RequiredForExploitationAmplify"
        Effect = "Allow"
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:StartJob"
        ]
        Resource = "*"
      },
      {
        # codecommit:GetRepository is required because amplify:CreateApp validates
        # that the caller can read the repo before accepting the app config.
        Sid    = "RequiredForExploitationCodeCommit"
        Effect = "Allow"
        Action = [
          "codecommit:GitPush",
          "codecommit:GitPull",
          "codecommit:GetRepository"
        ]
        Resource = aws_codecommit_repository.exploit_repo.arn
      },
      {
        # Amplify auto-creates an SNS topic (amplify_codecommit_topic) to receive
        # CodeCommit push notifications and trigger builds. CreateApp performs the
        # full plumbing as the caller: CreateTopic + Subscribe on the SNS side, and
        # PutRepositoryTriggers on the CodeCommit side to point the repo at the topic.
        Sid    = "RequiredForExploitationAmplifyCodeCommitNotificationsSNS"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic",
          "sns:Subscribe"
        ]
        Resource = "arn:aws:sns:*:${var.account_id}:amplify_codecommit_topic"
      },
      {
        Sid    = "RequiredForExploitationAmplifyCodeCommitTriggers"
        Effect = "Allow"
        Action = [
          "codecommit:GetRepositoryTriggers",
          "codecommit:PutRepositoryTriggers"
        ]
        Resource = aws_codecommit_repository.exploit_repo.arn
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "amplify:GetJob",
          "amplify:ListApps",
          "iam:ListAttachedUserPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ADMIN ROLE (Privilege Escalation Target)
# =============================================================================

# Admin role that will be passed as the service role for the Amplify app.
# This role trusts amplify.amazonaws.com because Amplify assumes it to run builds.
resource "aws_iam_role" "admin_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-amplify-001-to-admin-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-amplify-001-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+amplify-createapp+amplify-createbranch+amplify-startjob"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess policy to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# The admin role also needs CodeCommit access so Amplify can clone the repo during builds
resource "aws_iam_role_policy" "admin_role_codecommit_access" {
  provider = aws.prod
  name     = "pl-prod-amplify-001-to-admin-admin-role-codecommit-access"
  role     = aws_iam_role.admin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "codecommitCloneAccess"
        Effect = "Allow"
        Action = [
          "codecommit:GitPull"
        ]
        Resource = aws_codecommit_repository.exploit_repo.arn
      }
    ]
  })
}

# =============================================================================
# CODECOMMIT REPOSITORY (Exploit Staging)
# =============================================================================

# CodeCommit repository that the Amplify app connects to.
# The attacker pushes a malicious amplify.yml with build commands that
# use the admin role's credentials to escalate privileges.
resource "aws_codecommit_repository" "exploit_repo" {
  provider        = aws.prod
  repository_name = "pl-prod-amplify-001-to-admin-repo"
  description     = "CodeCommit repo for Amplify privilege escalation scenario"

  tags = {
    Name        = "pl-prod-amplify-001-to-admin-repo"
    Environment = var.environment
    Scenario    = "iam-passrole+amplify-createapp+amplify-createbranch+amplify-startjob"
    Purpose     = "exploit-repo"
  }
}

# CTF flag stored in SSM Parameter Store. Retrieved by the attacker once they
# reach administrator-equivalent permissions (AdministratorAccess grants
# ssm:GetParameter implicitly, so no extra IAM wiring is needed).
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/amplify-001-to-admin"
  description = "CTF flag for the amplify-001 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-amplify-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+amplify-createapp+amplify-createbranch+amplify-startjob"
    Purpose     = "ctf-flag"
  }
}
