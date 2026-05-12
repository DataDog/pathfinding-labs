# Lambda updater role in prod environment
resource "aws_iam_role" "lambda_updater" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-lambda-updater"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowDevRoleToAssume"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.dev_account_id}:role/pl-lambda-prod-updater"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy that allows lambda operations and PassRole
resource "aws_iam_policy" "lambda_updater" {
  provider = aws.prod
  name     = "pl-lambda-updater"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRoleAndLambda"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:InvokeFunction",
          "lambda:CreateFunction",
          "iam:PassRole",
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForExploitation"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "lambda:ListFunctions",
          "iam:GetRole",
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "lambda_updater" {
  provider   = aws.prod
  role       = aws_iam_role.lambda_updater.name
  policy_arn = aws_iam_policy.lambda_updater.arn
}

# Lambda admin role that can be passed via PassRole
resource "aws_iam_role" "lambda_admin" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-Lambda-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaToAssume"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Admin policy for the lambda admin role
resource "aws_iam_policy" "lambda_admin_policy" {
  provider = aws.prod
  name     = "pl-lambda-admin-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AdminAccess"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# Attach admin policy to lambda admin role
resource "aws_iam_role_policy_attachment" "lambda_admin" {
  provider   = aws.prod
  role       = aws_iam_role.lambda_admin.name
  policy_arn = aws_iam_policy.lambda_admin_policy.arn
}

resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/passrole-lambda-admin-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name     = "pl-prod-passrole-lambda-admin-to-admin-flag"
    Scenario = "passrole-lambda-admin"
    Purpose  = "ctf-flag"
  }
}
