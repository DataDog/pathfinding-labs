terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Role that can escalate its own privileges by modifying its own role policy
resource "aws_iam_role" "privesc_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-putrolepolicy-role"

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

# Policy that allows the role to modify its own role policy (self-privilege escalation)
resource "aws_iam_policy" "privesc_policy" {
  provider    = aws.prod
  name        = "pl-prod-one-hop-putrolepolicy-policy"
  description = "Allows the role to modify its own role policy for privilege escalation"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PutRolePolicy"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-one-hop-putrolepolicy-role"
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "privesc_policy_attachment" {
  provider   = aws.prod
  role       = aws_iam_role.privesc_role.name
  policy_arn = aws_iam_policy.privesc_policy.arn
}

