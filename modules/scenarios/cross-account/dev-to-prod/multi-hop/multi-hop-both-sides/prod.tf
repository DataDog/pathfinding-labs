# Jeremy user in prod environment (admin user with initial login profile)
resource "aws_iam_user" "jeremy" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-Jeremy"
}

# Admin policy for Jeremy user
resource "aws_iam_user_policy" "jeremy_admin" {
  provider = aws.prod
  name     = "pl-Jeremy-admin"
  user     = aws_iam_user.jeremy.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# Initial login profile for Jeremy (required for UpdateLoginProfile to work)
resource "aws_iam_user_login_profile" "jeremy" {
  provider = aws.prod
  user     = aws_iam_user.jeremy.name
}

# Trusts dev role in prod environment
resource "aws_iam_role" "trustsdev" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-trustsdev"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.dev_account_id}:user/pl-Josh"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Trusts dev policy with UpdateLoginProfile permission
resource "aws_iam_policy" "trustsdev" {
  provider = aws.prod
  name     = "pl-trustsdev"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationUpdateLoginProfile"
        Effect = "Allow"
        Action = [
          "iam:UpdateLoginProfile",
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "iam:GetLoginProfile",
          "iam:ListUsers",
          "iam:GetUser",
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach trustsdev policy to trustsdev role
resource "aws_iam_role_policy_attachment" "trustsdev" {
  provider   = aws.prod
  role       = aws_iam_role.trustsdev.name
  policy_arn = aws_iam_policy.trustsdev.arn
}

resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/multi-hop-both-sides-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name     = "pl-prod-multi-hop-both-sides-to-admin-flag"
    Scenario = "multi-hop-both-sides"
    Purpose  = "ctf-flag"
  }
}
