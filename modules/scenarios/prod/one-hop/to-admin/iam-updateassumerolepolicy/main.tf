# IAM UpdateAssumeRolePolicy privilege escalation to admin scenario
#
# This scenario demonstrates how a role with iam:UpdateAssumeRolePolicy permission
# can modify the trust policy of an admin role to grant themselves access.

# Admin role that the attacker will modify the trust policy of
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-updateassumerolepolicy-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"  # Initially trusts EC2 service
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-one-hop-updateassumerolepolicy-admin-role"
    Environment = var.environment
    Scenario    = "iam-updateassumerolepolicy"
    Target      = "admin"
  }
}

# Attach AdministratorAccess to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Starting role with UpdateAssumeRolePolicy permission
resource "aws_iam_role" "starting_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-updateassumerolepolicy-role"

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
    Name        = "pl-prod-one-hop-updateassumerolepolicy-role"
    Environment = var.environment
    Scenario    = "iam-updateassumerolepolicy"
    Purpose     = "starting-role"
  }
}

# Policy granting UpdateAssumeRolePolicy permission on the admin role
resource "aws_iam_role_policy" "starting_role_policy" {
  provider = aws.prod
  name     = "UpdateAssumeRolePolicyPermission"
  role     = aws_iam_role.starting_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowUpdateAssumeRolePolicy"
        Effect = "Allow"
        Action = [
          "iam:UpdateAssumeRolePolicy",
          "iam:GetRole"  # To verify the attack worked
        ]
        Resource = aws_iam_role.admin_role.arn
      },
      {
        Sid    = "AllowSelfIdentification"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}