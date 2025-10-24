# IAM UpdateAssumeRolePolicy privilege escalation to admin scenario
#
# This scenario demonstrates how a role with iam:UpdateAssumeRolePolicy permission
# can modify the trust policy of an admin role to grant themselves access.

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-uar-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-uar-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-updateassumerolepolicy"
    Purpose     = "starting-user"
  }
}

# Access key for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Basic policy for starting user
resource "aws_iam_user_policy" "starting_user_basic" {
  provider = aws.prod
  name     = "pl-prod-uar-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:GetUser"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-uar-to-admin-starting-role"
      }
    ]
  })
}

# Target admin role that the attacker will modify the trust policy of
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-uar-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com" # Initially trusts EC2 service
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-uar-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-updateassumerolepolicy"
    Target      = "admin"
  }
}

# Attach AdministratorAccess to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Starting role with UpdateAssumeRolePolicy permission
resource "aws_iam_role" "starting_role" {
  provider = aws.prod
  name     = "pl-prod-uar-to-admin-starting-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.starting_user.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-uar-to-admin-starting-role"
    Environment = var.environment
    Scenario    = "iam-updateassumerolepolicy"
    Purpose     = "starting-role"
  }
}

# Policy granting UpdateAssumeRolePolicy permission on the target role
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
          "iam:GetRole" # To verify the attack worked
        ]
        Resource = aws_iam_role.target_role.arn
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