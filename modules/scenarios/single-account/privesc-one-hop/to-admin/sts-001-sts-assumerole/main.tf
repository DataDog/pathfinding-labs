terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-sts-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-sts-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "sts-assumerole"
    Purpose     = "starting-user"
  }
}

# Access key for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for starting user with required permissions only
resource "aws_iam_user_policy" "starting_user_basic" {
  provider = aws.prod
  name     = "pl-prod-sts-001-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationAssumeRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-sts-001-to-admin-target-role"
      }
    ]
  })
}

# Admin role that can be directly assumed by the starting user
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-sts-001-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.starting_user.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-sts-001-to-admin-target-role"
    Environment = var.environment
    Scenario    = "sts-assumerole"
    Purpose     = "target-admin-role"
  }
}

# Attach AdministratorAccess policy to the role
resource "aws_iam_role_policy_attachment" "admin_policy_attachment" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/sts-001-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name     = "pl-prod-sts-001-to-admin-flag"
    Scenario = "sts-001-sts-assumerole"
    Purpose  = "ctf-flag"
  }
}
