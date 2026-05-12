terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Admin user for attacker account operations (analogous to prod's admin_user_for_cleanup)
resource "aws_iam_user" "admin_user" {
  force_destroy = true
  name          = "pl-attacker-admin-user"

  tags = {
    Name        = "pl-attacker-admin-user"
    Environment = "attacker"
    Purpose     = "attacker-admin"
  }
}

resource "aws_iam_user_policy_attachment" "admin_user" {
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_access_key" "admin_user" {
  user = aws_iam_user.admin_user.name
}
