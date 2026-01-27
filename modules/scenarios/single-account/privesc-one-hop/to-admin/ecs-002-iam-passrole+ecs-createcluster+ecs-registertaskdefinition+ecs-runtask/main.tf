# ECS PassRole privilege escalation scenario
#
# This scenario demonstrates how a user with ecs:CreateCluster, iam:PassRole,
# ecs:RegisterTaskDefinition, and ecs:RunTask can escalate privileges by
# creating an ECS cluster and running a Fargate task with a privileged role
# that grants the starting user admin access.

# Resource naming convention: pl-prod-ecs-002-to-admin-{resource-type}
# Provider: aws.prod (single-account scenario)

# =============================================================================
# STARTING USER (with access keys)
# =============================================================================

resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ecs-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ecs-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-runtask"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting the starting user the permissions needed for the attack
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-ecs-002-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "requiredPermissions"
        Effect = "Allow"
        Action = [
          "ecs:CreateCluster",
          "ecs:RegisterTaskDefinition",
          "ecs:RunTask"
        ]
        Resource = "*"
      },
      {
        Sid    = "requiredPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "helpfulAdditionalPermissions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ecs:DescribeTasks",
          "ecs:StopTask",
          "ecs:DeregisterTaskDefinition",
          "ecs:DeleteCluster",
          "iam:ListAttachedUserPolicies",
          "iam:DetachUserPolicy",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ROLE (with admin permissions)
# =============================================================================

# This is the privileged role that the ECS task will use
# The task can then attach the AdministratorAccess policy to the starting user
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-ecs-002-to-admin-target-role"

  # Trust policy allows ECS tasks to assume this role
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
    Name        = "pl-prod-ecs-002-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-runtask"
    Purpose     = "target-role"
  }
}

# Attach AdministratorAccess policy to the target role
# This gives the ECS task full admin permissions
resource "aws_iam_role_policy_attachment" "target_role_admin" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
