terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Role that can escalate its own privileges by modifying its own role policy
resource "aws_iam_role" "prod_self_privesc_putRolePolicy_role" {
  provider = aws.prod
  name     = "pl-prod-self-privesc-putRolePolicy-role-1"

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

# Policy that allows the role to modify its own role policy (self-privilege escalation)
resource "aws_iam_policy" "prod_self_privesc_putRolePolicy_policy" {
  provider = aws.prod
  name     = "pl-prod-self-privesc-putRolePolicy-policy"
  description = "Allows the role to modify its own role policy for privilege escalation"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PutRolePolicy"
        ]
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-self-privesc-putRolePolicy-role-1"
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "prod_self_privesc_putRolePolicy_policy_attachment" {
  provider = aws.prod
  role       = aws_iam_role.prod_self_privesc_putRolePolicy_role.name
  policy_arn = aws_iam_policy.prod_self_privesc_putRolePolicy_policy.arn
}
