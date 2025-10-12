terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Role that can escalate its own privileges by attaching policies to itself
resource "aws_iam_role" "prod_self_privesc_attachRolePolicy_role" {
  provider = aws.prod
  name     = "pl-prod-self-privesc-attachRolePolicy-role-1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.prod_account_id}:user/pl-pathfinder-starting-user-prod"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy that allows the role to attach policies to itself (self-privilege escalation)
resource "aws_iam_policy" "prod_self_privesc_attachRolePolicy_policy" {
  provider = aws.prod
  name     = "pl-prod-self-privesc-attachRolePolicy-policy"
  description = "Allows the role to attach policies to itself for privilege escalation"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy"
        ]
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-self-privesc-attachRolePolicy-role-1"
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "prod_self_privesc_attachRolePolicy_policy_attachment" {
  provider = aws.prod
  role       = aws_iam_role.prod_self_privesc_attachRolePolicy_role.name
  policy_arn = aws_iam_policy.prod_self_privesc_attachRolePolicy_policy.arn
}
