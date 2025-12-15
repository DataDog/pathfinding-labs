resource "aws_iam_role" "ops_role_with_assumeRole_star" {
  provider = aws.operations
  name     = "pl-x-account-ops-role-with-assume-role-star"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${var.operations_account_id}:user/pl-pathfinding-starting-user-operations"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "assume_role_star_policy" {
  provider    = aws.operations
  name        = "pl-x-account-assume-role-star-policy"
  description = "Allows the operations account to assume any role"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "sts:AssumeRole",
        Resource = "*"
      }

    ]
  })
}

// attach the policy 
resource "aws_iam_policy_attachment" "assume_role_star_policy_attachment" {
  provider   = aws.operations
  name       = "pl-x-account-assume-role-star-policy-attachment"
  roles      = [aws_iam_role.ops_role_with_assumeRole_star.name]
  policy_arn = aws_iam_policy.assume_role_star_policy.arn
}

