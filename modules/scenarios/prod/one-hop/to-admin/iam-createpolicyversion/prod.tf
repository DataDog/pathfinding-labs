terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Role that can escalate its own privileges by creating new policy versions
resource "aws_iam_role" "prod_self_privesc_createPolicyVersion_role" {
  provider = aws.prod
  name     = "pl-prod-self-privesc-createPolicyVersion-role-1"

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

# Policy that allows the role to create new versions of policies attached to itself
resource "aws_iam_policy" "prod_self_privesc_createPolicyVersion_policy" {
  provider = aws.prod
  name     = "pl-prod-self-privesc-createPolicyVersion-policy"
  description = "Allows the role to create new versions of policies for privilege escalation"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreatePolicyVersion",
          "iam:ListPolicyVersions"
        ]
        Resource = "arn:aws:iam::${var.prod_account_id}:policy/pl-prod-self-privesc-createPolicyVersion-policy"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:ListAttachedRolePolicies"
        ]
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-self-privesc-createPolicyVersion-role-1"
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "prod_self_privesc_createPolicyVersion_policy_attachment" {
  provider = aws.prod
  role       = aws_iam_role.prod_self_privesc_createPolicyVersion_role.name
  policy_arn = aws_iam_policy.prod_self_privesc_createPolicyVersion_policy.arn
}
