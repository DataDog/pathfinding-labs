# audit-user addon
#
# Provisions a read-only IAM user suitable for agent-based IAM reconnaissance.
# The user can enumerate IAM entities (iam:Get*, iam:List*) and confirm its own
# identity (sts:GetCallerIdentity), but has no write permissions.
#
# Credentials are exposed as Terraform outputs and merged into plabs output --raw
# under the "addon" key so the bench harness can inject them via audit_execute.

resource "aws_iam_user" "audit_user" {
  name = "pl-addon-audit-user"

  tags = {
    Name        = "pl-addon-audit-user"
    Environment = var.environment
    ManagedBy   = "plabs-addon"
    Purpose     = "audit-recon"
  }
}

resource "aws_iam_access_key" "audit_user" {
  user = aws_iam_user.audit_user.name
}

resource "aws_iam_user_policy" "audit_user_policy" {
  name = "pl-addon-audit-user-policy"
  user = aws_iam_user.audit_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAMReadOnly"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}
