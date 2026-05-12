terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# iam:PassRole + elasticmapreduce:RunJobFlow privilege escalation scenario
#
# This scenario demonstrates how an attacker with iam:PassRole and elasticmapreduce:RunJobFlow
# permissions can escalate privileges by creating an EMR cluster with an admin instance profile
# and executing a step via command-runner.jar that attaches AdministratorAccess to themselves.
#
# EMR requires TWO roles to be passed:
#   1. JobFlowRole (instance profile) - used by EC2 instances in the cluster, trusts ec2.amazonaws.com
#   2. ServiceRole - used by the EMR service itself, trusts elasticmapreduce.amazonaws.com

# Resource naming convention: pl-prod-emr-001-to-admin-{resource-type}
# Provider: aws.prod (single account scenario)

# ---------------------------------------------------------------------------
# Starting user
# ---------------------------------------------------------------------------

resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-emr-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-emr-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+elasticmapreduce-runjobflow"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Required permissions: iam:PassRole (scoped to both roles) + elasticmapreduce:RunJobFlow
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-emr-001-to-admin-starting-user-policy"
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
        Resource = [
          aws_iam_role.admin_role.arn,
          aws_iam_role.service_role.arn
        ]
      },
      {
        Sid    = "RequiredForExploitationRunJobFlow"
        Effect = "Allow"
        Action = [
          "elasticmapreduce:RunJobFlow"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Admin role (JobFlowRole) - instance profile for EC2 instances in EMR cluster
# ---------------------------------------------------------------------------

resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-emr-001-to-admin-admin-role"

  # Trusts ec2.amazonaws.com because this role is used as an EC2 instance profile
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-emr-001-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+elasticmapreduce-runjobflow"
    Purpose     = "admin-target"
  }
}

resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Instance profile required by EMR for the JobFlowRole
resource "aws_iam_instance_profile" "admin_instance_profile" {
  provider = aws.prod
  name     = "pl-prod-emr-001-to-admin-admin-instance-profile"
  role     = aws_iam_role.admin_role.name

  tags = {
    Name        = "pl-prod-emr-001-to-admin-admin-instance-profile"
    Environment = var.environment
    Scenario    = "iam-passrole+elasticmapreduce-runjobflow"
    Purpose     = "admin-instance-profile"
  }
}

# ---------------------------------------------------------------------------
# Service role - used by EMR service to manage cluster infrastructure
# ---------------------------------------------------------------------------

resource "aws_iam_role" "service_role" {
  provider = aws.prod
  name     = "pl-prod-emr-001-to-admin-service-role"

  # Trusts elasticmapreduce.amazonaws.com because this is the EMR service role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "elasticmapreduce.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-emr-001-to-admin-service-role"
    Environment = var.environment
    Scenario    = "iam-passrole+elasticmapreduce-runjobflow"
    Purpose     = "emr-service-role"
  }
}

resource "aws_iam_role_policy_attachment" "service_role_policy" {
  provider   = aws.prod
  role       = aws_iam_role.service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"
}
