terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# RoleA: Non-admin role that has iam:PutRolePolicy permission on RoleB
resource "aws_iam_role" "prod_role_a" {
  provider = aws.prod
  name     = "pl-prod-role-a-non-admin"

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

# Policy for RoleA - Allows PutRolePolicy only on RoleB
resource "aws_iam_policy" "prod_role_a_policy" {
  provider    = aws.prod
  name        = "pl-prod-role-a-putrolepolicy-policy"
  description = "Allows RoleA to modify RoleB's policies"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy"
        ]
        Resource = aws_iam_role.prod_role_b.arn
      }
    ]
  })
}

# Attach policy to RoleA
resource "aws_iam_role_policy_attachment" "prod_role_a_policy" {
  provider   = aws.prod
  role       = aws_iam_role.prod_role_a.name
  policy_arn = aws_iam_policy.prod_role_a_policy.arn
}

# RoleB: Admin role that trusts RoleA to assume it
resource "aws_iam_role" "prod_role_b" {
  provider = aws.prod
  name     = "pl-prod-role-b-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.prod_role_a.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# RoleB starts with no policies - RoleA will add admin policy during attack

# S3 bucket to demonstrate admin access
resource "aws_s3_bucket" "prod_admin_demo_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-admin-demo-bucket-${var.prod_account_id}-${var.resource_suffix}"
}

resource "aws_s3_bucket_versioning" "prod_admin_demo_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.prod_admin_demo_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Flag file to demonstrate successful admin access
resource "aws_s3_object" "admin_flag_file" {
  provider = aws.prod
  bucket   = aws_s3_bucket.prod_admin_demo_bucket.id
  key      = "admin-flag.txt"
  content  = "🎉 CONGRATULATIONS! You have successfully exploited the PutRolePolicy privilege escalation!\n\nThis file demonstrates that an attacker with iam:PutRolePolicy permission on a non-admin role can gain full administrative access.\n\nAttack Path:\n1. RoleA (non-admin) → Uses iam:PutRolePolicy to add admin policy to RoleB\n2. RoleA → Assumes RoleB (which now has admin permissions)\n3. RoleB → Full admin access to AWS resources\n\nThis is a common privilege escalation technique in AWS environments.\n\nFlag: PATHFINDER-PUTROLEPOLICY-NONADMIN-ESCALATION-2024"
  etag     = md5("🎉 CONGRATULATIONS! You have successfully exploited the PutRolePolicy privilege escalation!\n\nThis file demonstrates that an attacker with iam:PutRolePolicy permission on a non-admin role can gain full administrative access.\n\nAttack Path:\n1. RoleA (non-admin) → Uses iam:PutRolePolicy to add admin policy to RoleB\n2. RoleA → Assumes RoleB (which now has admin permissions)\n3. RoleB → Full admin access to AWS resources\n\nThis is a common privilege escalation technique in AWS environments.\n\nFlag: PATHFINDER-PUTROLEPOLICY-NONADMIN-ESCALATION-2024")
}
