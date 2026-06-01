terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.dev, aws.prod]
    }
  }
}

# Scenario-specific starting user in the dev account. Each lab provisions its
# own starting principal + access key so plabs can surface dedicated credentials
# in the TUI / demo scripts without coupling scenarios via a shared user.
resource "aws_iam_user" "starting_user" {
  provider      = aws.dev
  force_destroy = true
  name          = "pl-dev-ssm-ec2-starting-user"

  tags = {
    Name        = "pl-dev-ssm-ec2-starting-user"
    Environment = "dev"
    Scenario    = "ssm-startsession-ec2-admin"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user" {
  provider = aws.dev
  user     = aws_iam_user.starting_user.name
}

# Grant the scenario-specific dev starting user the permissions needed to
# begin the attack:
# - sts:AssumeRole on the prod pivot role (required for exploitation)
# - iam:ListRoles (helpful for discovering the assumable prod role)
resource "aws_iam_user_policy" "starting_user_cross_account" {
  provider = aws.dev
  name     = "pl-ssm-ec2-cross-account"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RequiredForExploitationAssumeRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-ssm-ec2-pivot-role"
      },
      {
        Sid      = "HelpfulForReconAndMonitoring"
        Effect   = "Allow"
        Action   = ["iam:ListRoles"]
        Resource = "*"
      }
    ]
  })
}
