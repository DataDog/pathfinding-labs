# SageMaker CreateNotebookInstance privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and sagemaker:CreateNotebookInstance
# can create a SageMaker notebook instance with an administrative role, then generate a presigned
# URL to access the Jupyter environment and execute commands with elevated privileges.

# Resource naming convention: pl-prod-sagemaker-001-to-admin-{resource-type}
# For single account scenarios, use provider = aws.prod

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-sagemaker-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-sagemaker-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+sagemaker-createnotebookinstance"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user with PassRole and SageMaker permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-sagemaker-001-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "requiredPermissions1"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.passable_role.arn
      },
      {
        Sid    = "requiredPermissions2"
        Effect = "Allow"
        Action = [
          "sagemaker:CreateNotebookInstance"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions1"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions2"
        Effect = "Allow"
        Action = [
          "sagemaker:CreatePresignedNotebookInstanceUrl",
          "sagemaker:DescribeNotebookInstance",
          "sagemaker:ListNotebookInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions3"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Passable admin role that will be passed to SageMaker notebook instance
resource "aws_iam_role" "passable_role" {
  provider = aws.prod
  name     = "pl-prod-sagemaker-001-to-admin-passable-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-sagemaker-001-to-admin-passable-role"
    Environment = var.environment
    Scenario    = "iam-passrole+sagemaker-createnotebookinstance"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the passable role
resource "aws_iam_role_policy_attachment" "passable_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.passable_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
