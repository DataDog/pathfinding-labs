resource "aws_iam_role" "prod_role_trusts_operations" {
  provider = aws.prod
  name     = "pl-x-account-prod-role-trusts-operations"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${var.operations_account_id}:root"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "prod_role_trusts_operations" {
  provider   = aws.prod
  role       = aws_iam_role.prod_role_trusts_operations.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

resource "aws_iam_role" "prod_admin_role_trusts_operations" {
  provider = aws.prod
  name     = "pl-x-account-prod-admin-role-trusts-operations"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${var.operations_account_id}:root"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "prod_admin_role_trusts_operations" {
  provider   = aws.prod
  role       = aws_iam_role.prod_admin_role_trusts_operations.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}


// create a prod_privesc_role that will have iam:putrolepolicy permissions

resource "aws_iam_role" "prod_admin_role" {
  provider = aws.prod
  name     = "pl-x-account-prod-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${var.operations_account_id}:root"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}