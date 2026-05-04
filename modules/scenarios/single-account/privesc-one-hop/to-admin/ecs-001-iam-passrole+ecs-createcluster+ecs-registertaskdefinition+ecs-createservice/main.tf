terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# PassRole + ECS CreateCluster + RegisterTaskDefinition + CreateService privilege escalation scenario
#
# This scenario demonstrates how a user with ecs:CreateCluster, iam:PassRole,
# ecs:RegisterTaskDefinition, and ecs:CreateService can escalate privileges by
# creating an ECS cluster and service with an admin role. The ECS task runs a
# container that attaches AdministratorAccess policy to the starting user.

# Resource naming convention: pl-prod-ecs-001-to-admin-{resource-type}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ecs-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ecs-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-createservice"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with required permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-ecs-001-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationECS"
        Effect = "Allow"
        Action = [
          "ecs:CreateCluster",
          "ecs:RegisterTaskDefinition",
          "ecs:CreateService"
        ]
        Resource = "*"
      },
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "iam:ListAttachedUserPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target role that will be passed to ECS (has admin permissions)
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-ecs-001-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-ecs-001-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-createservice"
    Purpose     = "target-role"
  }
}

# Attach admin policy to target role (this is what makes it valuable)
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Policy allowing the target role to attach policies to users (for the attack)
resource "aws_iam_role_policy" "target_role_escalation_policy" {
  provider = aws.prod
  name     = "pl-prod-ecs-001-to-admin-escalation-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:AttachUserPolicy",
          "iam:ListUsers"
        ]
        Resource = "*"
      }
    ]
  })
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/ecs-001-to-admin"
  description = "CTF flag for the ecs-001 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-ecs-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-createservice"
    Purpose     = "ctf-flag"
  }
}
