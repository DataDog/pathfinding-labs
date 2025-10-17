# IAM UpdateLoginProfile privilege escalation to admin scenario
#
# This scenario demonstrates how a role with iam:UpdateLoginProfile permission
# can escalate to administrative privileges by changing the console password
# of an existing admin user who already has a login profile.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Admin user that will be the target of privilege escalation
# This user has AdministratorAccess AND an existing console password (login profile)
resource "aws_iam_user" "admin_user" {
  provider = aws.prod
  name     = "pl-ulp-admin"

  tags = {
    Name        = "pl-ulp-admin"
    Environment = var.environment
    Scenario    = "iam-updateloginprofile"
    Purpose     = "target-admin-user"
  }
}

# Attach AdministratorAccess to the admin user
resource "aws_iam_user_policy_attachment" "admin_access" {
  provider   = aws.prod
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}


# Create an existing login profile for the admin user
# This represents a pre-existing console password that the attacker will update
resource "aws_iam_user_login_profile" "admin_login_profile" {
  provider                = aws.prod
  user                    = aws_iam_user.admin_user.name
  password_reset_required = false

}

# Role that can update login profiles (privilege escalation vector)
resource "aws_iam_role" "privesc_role" {
  provider = aws.prod
  name     = "pl-ulp-ursula"

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

  tags = {
    Name        = "pl-ulp-ursula"
    Environment = var.environment
    Scenario    = "iam-updateloginprofile"
    Purpose     = "starting-role"
  }
}

# Policy that allows updating login profiles for the admin user
resource "aws_iam_policy" "privesc_policy" {
  provider    = aws.prod
  name        = "pl-prod-one-hop-updateloginprofile-policy"
  description = "Allows updating login profiles for the admin user"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:UpdateLoginProfile",
          "iam:GetLoginProfile" # To check if login profile exists
        ]
        Resource = aws_iam_user.admin_user.arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:GetUser",          # To get user details
          "sts:GetCallerIdentity" # For identity verification
        ]
        Resource = "*"
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