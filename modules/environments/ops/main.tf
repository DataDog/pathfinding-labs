terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# =============================================================================
# BUDGET ALERTS
# =============================================================================
# AWS Budgets to protect against unexpected costs
# Alerts at 50%, 80%, 100% actual spend and 100% forecasted spend

resource "aws_budgets_budget" "monthly_cost" {
  count = var.enable_budget_alerts && var.budget_alert_email != "" ? 1 : 0

  name         = "pl-ops-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Alert at 50% actual spend
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # Alert at 80% actual spend
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # Alert at 100% actual spend
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # Alert when forecast exceeds 100%
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}

# Pathfinding starting user for operations environment
resource "aws_iam_user" "pathfinding_starting_user" {
  force_destroy = true
  name          = "pl-pathfinding-starting-user-operations"
}

# Access key for the pathfinding starting user
resource "aws_iam_access_key" "pathfinding_starting_user" {
  user = aws_iam_user.pathfinding_starting_user.name
}

# Create admin user for cleanup scripts
resource "aws_iam_user" "admin_user_for_cleanup" {
  force_destroy = true
  name          = "pl-admin-user-for-cleanup-scripts"
}

# Access key for the admin cleanup user
resource "aws_iam_access_key" "admin_user_for_cleanup" {
  user = aws_iam_user.admin_user_for_cleanup.name
}

# Attach AdministratorAccess policy to cleanup user
resource "aws_iam_user_policy_attachment" "admin_user_for_cleanup_admin_access" {
  user       = aws_iam_user.admin_user_for_cleanup.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create readonly user for demo script observation steps
resource "aws_iam_user" "readonly_user" {
  force_destroy = true
  name          = "pl-readonly-user-ops"
  tags = {
    Name        = "pl-readonly-user-ops"
    Environment = "ops"
    Purpose     = "readonly-for-demo-scripts"
  }
}

# Attach ReadOnlyAccess policy to readonly user
resource "aws_iam_user_policy_attachment" "readonly_user_access" {
  user       = aws_iam_user.readonly_user.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Access key for the readonly user
resource "aws_iam_access_key" "readonly_user" {
  user = aws_iam_user.readonly_user.name
}

# Basic policy for the pathfinding starting user (minimal permissions)
resource "aws_iam_user_policy" "pathfinding_starting_user_basic" {
  name = "pl-pathfinding-starting-user-basic-policy"
  user = aws_iam_user.pathfinding_starting_user.name

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
      }
    ]
  })
}




# // IAM Role that trusts datadog to assume it

# resource "aws_iam_role" "datadog_role_no_sts_assume_role" {
#   name = "datadog_role_no_sts_assume_role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           AWS: "arn:aws:iam::464622532012:root"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# // IAM Role that trusts datadog to assume it but has sts:AssumeRole policy attached

# resource "aws_iam_role" "datadog_role" {
#   name = "datadog_role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           AWS: "arn:aws:iam::464622532012:root"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# resource "aws_iam_policy" "datadog_policy" {
#   name        = "datadog_policy"
#   description = "Allows datadog to assume the role"

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = "sts:AssumeRole",
#         Resource = "*"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "datadog_policy" {
#   role       = aws_iam_role.datadog_role.name
#   policy_arn = aws_iam_policy.datadog_policy.arn
# }


# // IAM user that has sts assume role permission

# resource "aws_iam_user" "datadog_user" {
#   name = "datadog_user"
# }

# resource "aws_iam_user_policy" "datadog_user_policy" {
#   name = "datadog_user_policy"
#   user = aws_iam_user.datadog_user.name

#   policy = aws_iam_policy.datadog_policy.policy
# }


# // role that trust prod resources to assume it

# // create a operations_privesc_role that will have iam:putrolepolicy permissions

# resource "aws_iam_role" "operations_admin_role_trusts_prod_and_dev" {
#   name = "operations_admin_role_trusts_prod_and_dev"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           AWS = [
#             "arn:aws:iam::${var.prod_account_id}:root",
#             "arn:aws:iam::${var.dev_account_id}:root"
#           ]
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# // create a policy called operations_privesc_policy that will have iam:putrolepolicy permissions

# resource "aws_iam_policy" "operations_privesc_policy" {
#   name        = "operations_privesc_policy"
#   description = "Allows privesc"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "iam:PutRolePolicy"
#         ],
#         Resource = "*"
#       }
#     ]
#   })
# }

# // attach the policy to the role

# resource "aws_iam_role_policy_attachment" "operations_privesc_policy" {
#   role       = aws_iam_role.operations_admin_role_trusts_prod_and_dev.name
#   policy_arn = aws_iam_policy.operations_privesc_policy.arn
# }



# // create an ecr repository

# resource "aws_ecr_repository" "ubuntu" {
#   name = "ubuntu"
# }

# // allow prod to download from the ecr repository

# resource "aws_ecr_repository_policy" "prod_ecr_policy" {
#   repository = aws_ecr_repository.ubuntu.name

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#             AWS = "arn:aws:iam::${var.prod_account_id}:root"
#         }
#         Action = [
#             "ecr:GetDownloadUrlForLayer",
#             "ecr:BatchGetImage",
#             "ecr:BatchCheckLayerAvailability",
#             "ecr:GetAuthorizationToken",
#           ],
#           }
#     ]
#   })
# }

# // create a role that trusts terraform cloud oidc provider

# resource "aws_iam_role" "terraform_cloud_oidc_role" {
#   name = "terraform_cloud_oidc_role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           Federated = "arn:aws:iam::464622532012:oidc-provider/app.terraform.io"
#         },
#         "Action": "sts:AssumeRoleWithWebIdentity",
#       "Condition": {
#         "StringEquals": {
#           "app.terraform.io:aud": "aws.workload.identity"
#         },
#         "StringLike": {
#           "app.terraform.io:sub": "organization:org:project:workspacesname:workspace:*:run_phase:*"
#         }
#       }
#     }
#   ]
# })
# }


# // create a Deployment Role in Ops

# resource "aws_iam_role" "Deployement" {
#   name = "Deployement"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#          AWS = "arn:aws:iam::${var.operations_account_id}:root"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "Deployementadmin" {
#   role = aws_iam_role.Deployement.name
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
# }
