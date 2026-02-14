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

  name         = "pl-dev-monthly-budget"
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

# Pathfinding starting user for dev environment
resource "aws_iam_user" "pathfinding_starting_user" {
  name = "pl-pathfinding-starting-user-dev"
}

# Access key for the pathfinding starting user
resource "aws_iam_access_key" "pathfinding_starting_user" {
  user = aws_iam_user.pathfinding_starting_user.name
}

# Create admin user for cleanup scripts
resource "aws_iam_user" "admin_user_for_cleanup" {
  name = "pl-admin-user-for-cleanup-scripts"
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



# //create a role with no permissions called role_with_no_permissions

# resource "aws_iam_role" "role_with_no_permissions" {
#   name = "role_with_no_permissions"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           AWS = "arn:aws:iam::${var.dev_account_id}:root"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# // create a role that truss the ec2 service and attach the AdministratorAccess policy to it

# resource "aws_iam_role" "ec2_trust_role" {
#   name = "ec2_trust_role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ec2_trust_role" {
#   role       = aws_iam_role.ec2_trust_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
# }




# // create another role called privesc role that will have the permissions iam:passrole and ec2:runinstances

# resource "aws_iam_role" "privesc_role" {
#   name = "privesc_role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           AWS = "arn:aws:iam::${var.operations_account_id}:root"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# // create a policy called privesc_policy that will have the permissions iam:passrole and ec2:runinstances

# resource "aws_iam_policy" "privesc_policy" {
#   name        = "privesc_policy"
#   description = "Allows privesc"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "iam:PassRole",
#           "ec2:RunInstances"
#         ],
#         Resource = "*"
#       }
#     ]
#   })
# }

# // attach the policy to the role

# resource "aws_iam_role_policy_attachment" "privesc_policy" {
#   role       = aws_iam_role.privesc_role.name
#   policy_arn = aws_iam_policy.privesc_policy.arn
# }


# ///////////////////////////////
# // Role that trusts github repo
# ///////////////////////////////


# resource "aws_iam_role" "trust-me" {
#   name = "t_rodman"
#   assume_role_policy = <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Action": "sts:AssumeRoleWithWebIdentity",
#       "Principal": {
#         "Federated": "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
#       },
#       "Condition": {
#         "StringLike": {
#                     "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
#                     "token.actions.githubusercontent.com:sub": "repo:cloudfoxable/trust-me-demo:*"
#                 }
#       },
#       "Effect": "Allow",
#       "Sid": ""
#     }
#   ]
# }
# EOF
# }


# // create an identity provider for the github OIDC flow
# resource "aws_iam_openid_connect_provider" "github" {
#   client_id_list = ["sts.amazonaws.com"]
#   thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
#   url = "https://token.actions.githubusercontent.com"
# }


# // create a policy to allow the github OIDC role to read the flag
# resource "aws_iam_policy" "trust-me" {
#   name = "trust-me"
#   policy = <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Sid": "AllowAssumeRole",
#       "Effect": "Allow",
#       "Action": [
#         "sts:AssumeRole"
#       ],
#       "Resource": [
#         "*"
#       ]
#     }   
#   ]
# }
# EOF
# }

# // attach the policy to the github OIDC role
# resource "aws_iam_role_policy_attachment" "trust-me" {
#   role = aws_iam_role.trust-me.name
#   policy_arn = aws_iam_policy.trust-me.arn
# }



# // create an identity provider for the EKS OIDC flow
# resource "aws_iam_openid_connect_provider" "eks" {
#   client_id_list = ["sts.amazonaws.com"]
#   thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
#   url = "https://oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E2E8B1B6B1AE8D"
# }

# // create a role that trusts the EKS OIDC provider
# resource "aws_iam_role" "eks-dev" {
#   name = "eks-dev"
#   assume_role_policy = <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Action": "sts:AssumeRoleWithWebIdentity",
#       "Principal": {
#         "Federated": "arn:aws:iam::${var.dev_account_id}:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E2E8B1B6B1AE8D"
#       },
#       "Condition": {
#         "StringEquals": {
#           "oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E2E8B1B6B1AE8D:sub": "system:serviceaccount:default:default"
#         }
#       },
#       "Effect": "Allow",
#       "Sid": ""
#     }
#   ]
# }
# EOF
# }

# // create a policy to allow the EKS OIDC role to read the flag
# resource "aws_iam_policy" "eks-dev" {
#   name = "eks-dev"
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid = "AllowAssumeRole",
#         Effect = "Allow",
#         Action = [
#           "sts:AssumeRole",
#           "ec2:*",
#           "lambda:*",
#           "cloudformation:*",
#           "ssm:*",
#         ],
#         Resource = [
#           "*"
#         ]
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "eks-dev" {
#   role = aws_iam_role.eks-dev.name
#   policy_arn = aws_iam_policy.eks-dev.arn
# }





