# AttachRolePolicy + UpdateAssumeRolePolicy privilege escalation scenario
#
# This scenario demonstrates how a user with iam:AttachRolePolicy and
# iam:UpdateAssumeRolePolicy can escalate to admin by:
# 1. Attaching AdministratorAccess policy to a target role
# 2. Updating the target role's trust policy to allow themselves to assume it
# 3. Assuming the now-admin role (no sts:AssumeRole permission needed in user policy)

# Resource naming convention: pl-prod-arpuar-to-admin-{resource-type}
# "arpuar" = AttachRolePolicy+UpdateAssumeRolePolicy

# ============================================================================
# STARTING USER (Scenario Entry Point)
# ============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-arpuar-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-arpuar-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-attachrolepolicy+iam-updateassumerolepolicy"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting the exploitable permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-arpuar-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "requiredPermissions"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:UpdateAssumeRolePolicy"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "helpfulAdditionalPermissions"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole",
          "iam:ListAttachedRolePolicies",
          "iam:GetUserPolicy"
        ]
        Resource = "*"
      },
      {
        Sid    = "utilityPermissions"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# TARGET ROLE (Initially Not Assumable by Starting User)
# ============================================================================

# Target role with NO permissions initially
# Trust policy does NOT trust the starting user (this is key to the attack)
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-arpuar-to-admin-target-role"

  # Initial trust policy - trusts root but NOT the starting user
  # The attack will modify this to allow the starting user
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-arpuar-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-attachrolepolicy+iam-updateassumerolepolicy"
    Purpose     = "target-role"
  }
}

# Note: No policies attached initially
# The attack will attach AdministratorAccess during exploitation
