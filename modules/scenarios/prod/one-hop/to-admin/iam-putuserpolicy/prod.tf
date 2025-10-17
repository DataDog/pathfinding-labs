terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Starting user that will demonstrate the privilege escalation
resource "aws_iam_user" "privesc_user" {
  provider = aws.prod
  name     = "pl-pup-user"
}

# Create access key for the user (for demo purposes)
resource "aws_iam_access_key" "privesc_user_key" {
  provider = aws.prod
  user     = aws_iam_user.privesc_user.name
}

# Policy granting PutUserPolicy permission (the privilege escalation vector)
resource "aws_iam_policy" "putuserpolicy_policy" {
  provider    = aws.prod
  name        = "pl-prod-one-hop-putuserpolicy-policy"
  description = "Allows PutUserPolicy on any user - privilege escalation vector"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PutUserPolicy"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:GetUser",
          "iam:ListUserPolicies"
        ]
        Resource = aws_iam_user.privesc_user.arn
      }
    ]
  })
}

# Attach the policy to the user
resource "aws_iam_user_policy_attachment" "user_policy_attachment" {
  provider   = aws.prod
  user       = aws_iam_user.privesc_user.name
  policy_arn = aws_iam_policy.putuserpolicy_policy.arn
}

# Also create a role variant that can be assumed by the pathfinder starting user
resource "aws_iam_role" "privesc_role" {
  provider = aws.prod
  name     = "pl-pup-adam"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:user/pl-pathfinder-starting-user-prod"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach the policy to the role as well
resource "aws_iam_role_policy_attachment" "role_policy_attachment" {
  provider   = aws.prod
  role       = aws_iam_role.privesc_role.name
  policy_arn = aws_iam_policy.putuserpolicy_policy.arn
}