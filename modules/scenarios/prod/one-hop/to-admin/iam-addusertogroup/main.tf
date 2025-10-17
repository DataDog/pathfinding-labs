terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Admin group with AdministratorAccess policy
resource "aws_iam_group" "admin_group" {
  provider = aws.prod
  name     = "pl-aug-admin-group"
}

# Attach AdministratorAccess managed policy to the group
resource "aws_iam_group_policy_attachment" "admin_policy" {
  provider   = aws.prod
  group      = aws_iam_group.admin_group.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create the user that will perform self-escalation (NOT initially in the admin group)
resource "aws_iam_user" "start_user" {
  provider = aws.prod
  name     = "pl-aug-start-user"

  tags = {
    Name        = "pl-aug-start-user"
    Environment = var.environment
    Scenario    = "iam-addusertogroup"
    Purpose     = "self-escalation-user"
  }
}

# Create access key for the start user
resource "aws_iam_access_key" "start_user_key" {
  provider = aws.prod
  user     = aws_iam_user.start_user.name
}

# Policy that allows the user to add themselves to the admin group (the vulnerability)
resource "aws_iam_user_policy" "privesc_policy" {
  provider = aws.prod
  name     = "pl-aug-addusertogroup"
  user     = aws_iam_user.start_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:AddUserToGroup"
        ]
        Resource = aws_iam_group.admin_group.arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:GetGroup",
          "iam:ListGroupsForUser",
          "iam:ListGroups",
          "iam:GetUser",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}
