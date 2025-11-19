# =============================================================================
# Tool Testing: Effective Permissions Evaluation
# =============================================================================
#
# This scenario creates 40 principals (1 starting user + 39 test principals)
# to test CSPM and security tools' ability to accurately evaluate effective
# permissions across:
# - Different admin access patterns (managed, customer, inline, group, multi-policy)
# - Explicit denies that block admin access
# - Permission boundaries that block admin access
# - Edge cases like NotAction, split policies, policy mismatches
#
# Admin Definition: You have * on * without any IAM denies (ignoring resource denies)
#
# Resource naming convention: pl-prod-epe-{principal-type}-{isAdmin|notAdmin}-{description}

# =============================================================================
# CUSTOMER MANAGED POLICIES
# =============================================================================

# Admin customer managed policy - full access
resource "aws_iam_policy" "admin_customer_policy" {
  provider = aws.prod
  name     = "pl-prod-epe-admin-customer-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-epe-admin-customer-policy"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
  }
}

# IAM-only policy
resource "aws_iam_policy" "iam_only_policy" {
  provider = aws.prod
  name     = "pl-prod-epe-iam-only-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iam:*"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-epe-iam-only-policy"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
  }
}

# NotAction IAM policy (allows everything except IAM)
resource "aws_iam_policy" "notaction_iam_policy" {
  provider = aws.prod
  name     = "pl-prod-epe-notaction-iam-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        NotAction = ["iam:*"]
        Resource  = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-epe-notaction-iam-policy"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
  }
}

# S3-only policy
resource "aws_iam_policy" "s3_only_policy" {
  provider = aws.prod
  name     = "pl-prod-epe-s3-only-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-epe-s3-only-policy"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
  }
}

# NotAction S3 policy (allows everything except S3)
resource "aws_iam_policy" "notaction_s3_policy" {
  provider = aws.prod
  name     = "pl-prod-epe-notaction-s3-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        NotAction = ["s3:*"]
        Resource  = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-epe-notaction-s3-policy"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
  }
}

# Many services policy (together equals * on *)
resource "aws_iam_policy" "many_services_policy" {
  provider = aws.prod
  name     = "pl-prod-epe-many-services-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*", "s3:*", "iam:*", "lambda:*", "cloudwatch:*", "logs:*",
          "rds:*", "dynamodb:*", "sns:*", "sqs:*", "sts:*", "kms:*",
          "apigateway:*", "cloudformation:*", "elasticloadbalancing:*",
          "autoscaling:*", "route53:*", "cloudfront:*", "acm:*", "waf:*",
          "guardduty:*", "securityhub:*", "config:*", "cloudtrail:*",
          "organizations:*", "ssm:*", "secretsmanager:*", "ecs:*", "eks:*",
          "elasticache:*", "redshift:*", "athena:*", "glue:*", "kinesis:*",
          "firehose:*", "backup:*", "events:*", "states:*", "batch:*",
          "ecr:*", "codebuild:*", "codepipeline:*", "codecommit:*",
          "codedeploy:*", "elasticbeanstalk:*", "lightsail:*", "glacier:*",
          "storagegateway:*", "transfer:*", "workspaces:*", "appstream:*",
          "chime:*", "connect:*", "workmail:*", "ses:*", "pinpoint:*",
          "cognito-idp:*", "cognito-identity:*", "appsync:*", "amplify:*",
          "devicefarm:*", "mobilehub:*", "application-autoscaling:*",
          "appconfig:*", "appmesh:*", "cloud9:*", "codestar:*",
          "datasync:*", "dax:*", "discovery:*", "dms:*", "ds:*",
          "elasticfilesystem:*", "elasticmapreduce:*", "elastictranscoder:*",
          "fms:*", "forecast:*", "frauddetector:*", "fsx:*",
          "gamelift:*", "globalaccelerator:*", "greengrass:*", "groundstation:*",
          "health:*", "imagebuilder:*", "importexport:*", "inspector:*",
          "iot:*", "iotanalytics:*", "iotevents:*", "kafka:*",
          "kendra:*", "lakeformation:*", "license-manager:*", "macie:*",
          "managedblockchain:*", "mediaconnect:*", "mediaconvert:*",
          "medialive:*", "mediapackage:*", "mediastore:*", "mediatailor:*",
          "mgh:*", "mq:*", "neptune:*", "opsworks:*", "opsworks-cm:*",
          "personalize:*", "polly:*", "qldb:*", "quicksight:*",
          "ram:*", "rekognition:*", "resource-groups:*", "robomaker:*",
          "sagemaker:*", "savingsplans:*", "schemas:*", "sdb:*",
          "servicecatalog:*", "servicediscovery:*", "servicequotas:*",
          "shield:*", "signer:*", "snowball:*", "support:*",
          "swf:*", "tag:*", "textract:*", "transcribe:*",
          "translate:*", "trustedadvisor:*", "wafv2:*", "wellarchitected:*",
          "workdocs:*", "worklink:*", "xray:*", "access-analyzer:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-epe-many-services-policy"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
  }
}

# Boundary policy - allows nothing
resource "aws_iam_policy" "boundary_allows_nothing" {
  provider = aws.prod
  name     = "pl-prod-epe-boundary-allows-nothing"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-epe-boundary-allows-nothing"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
  }
}

# Boundary policy - EC2 DescribeInstances only
resource "aws_iam_policy" "boundary_ec2only" {
  provider = aws.prod
  name     = "pl-prod-epe-boundary-ec2only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ec2:DescribeInstances"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-epe-boundary-ec2only"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
  }
}

# Boundary policy - NotAction EC2 (allows only EC2 DescribeInstances)
resource "aws_iam_policy" "boundary_notaction_ec2only" {
  provider = aws.prod
  name     = "pl-prod-epe-boundary-notaction-ec2only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        NotAction = ["ec2:DescribeInstances"]
        Resource  = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-epe-boundary-notaction-ec2only"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
  }
}

# Boundary policy - IAM only
resource "aws_iam_policy" "boundary_iam_only" {
  provider = aws.prod
  name     = "pl-prod-epe-boundary-iam-only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iam:*"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-epe-boundary-iam-only"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
  }
}

# =============================================================================
# IAM GROUPS
# =============================================================================

# Group with AWS managed admin policy
resource "aws_iam_group" "admin_awsmanaged" {
  provider = aws.prod
  name     = "pl-prod-epe-group-admin-awsmanaged"
}

resource "aws_iam_group_policy_attachment" "admin_awsmanaged" {
  provider   = aws.prod
  group      = aws_iam_group.admin_awsmanaged.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Group with customer managed admin policy
resource "aws_iam_group" "admin_customermanaged" {
  provider = aws.prod
  name     = "pl-prod-epe-group-admin-customermanaged"
}

resource "aws_iam_group_policy_attachment" "admin_customermanaged" {
  provider   = aws.prod
  group      = aws_iam_group.admin_customermanaged.name
  policy_arn = aws_iam_policy.admin_customer_policy.arn
}

# Group with inline admin policy
resource "aws_iam_group" "admin_inline" {
  provider = aws.prod
  name     = "pl-prod-epe-group-admin-inline"
}

resource "aws_iam_group_policy" "admin_inline" {
  provider = aws.prod
  name     = "pl-prod-epe-group-admin-inline-policy"
  group    = aws_iam_group.admin_inline.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# STARTING USER
# =============================================================================

resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-epe-starting-user"

  tags = {
    Name        = "pl-prod-epe-starting-user"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    Purpose     = "starting-user-for-role-assumption"
  }
}

resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

resource "aws_iam_user_policy" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-epe-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::${var.account_id}:role/pl-prod-epe-role-*"
      },
      {
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# ISADMIN USERS - SINGLE POLICY (3 users)
# =============================================================================

# 1. User with AWS managed admin policy
resource "aws_iam_user" "isadmin_awsmanaged" {
  provider = aws.prod
  name     = "pl-prod-epe-user-isAdmin-awsmanaged"

  tags = {
    Name        = "pl-prod-epe-user-isAdmin-awsmanaged"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_access_key" "isadmin_awsmanaged" {
  provider = aws.prod
  user     = aws_iam_user.isadmin_awsmanaged.name
}

resource "aws_iam_user_policy_attachment" "isadmin_awsmanaged" {
  provider   = aws.prod
  user       = aws_iam_user.isadmin_awsmanaged.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 2. User with customer managed admin policy
resource "aws_iam_user" "isadmin_customermanaged" {
  provider = aws.prod
  name     = "pl-prod-epe-user-isAdmin-customermanaged"

  tags = {
    Name        = "pl-prod-epe-user-isAdmin-customermanaged"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_access_key" "isadmin_customermanaged" {
  provider = aws.prod
  user     = aws_iam_user.isadmin_customermanaged.name
}

resource "aws_iam_user_policy_attachment" "isadmin_customermanaged" {
  provider   = aws.prod
  user       = aws_iam_user.isadmin_customermanaged.name
  policy_arn = aws_iam_policy.admin_customer_policy.arn
}

# 3. User with inline admin policy
resource "aws_iam_user" "isadmin_inline" {
  provider = aws.prod
  name     = "pl-prod-epe-user-isAdmin-inline"

  tags = {
    Name        = "pl-prod-epe-user-isAdmin-inline"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_access_key" "isadmin_inline" {
  provider = aws.prod
  user     = aws_iam_user.isadmin_inline.name
}

resource "aws_iam_user_policy" "isadmin_inline" {
  provider = aws.prod
  name     = "pl-prod-epe-user-isAdmin-inline-policy"
  user     = aws_iam_user.isadmin_inline.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# ISADMIN USERS - GROUP MEMBERSHIP (3 users)
# =============================================================================

# 4. User in group with AWS managed admin policy
resource "aws_iam_user" "isadmin_via_group_awsmanaged" {
  provider = aws.prod
  name     = "pl-prod-epe-user-isAdmin-via-group-awsmanaged"

  tags = {
    Name        = "pl-prod-epe-user-isAdmin-via-group-awsmanaged"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_access_key" "isadmin_via_group_awsmanaged" {
  provider = aws.prod
  user     = aws_iam_user.isadmin_via_group_awsmanaged.name
}

resource "aws_iam_user_group_membership" "isadmin_via_group_awsmanaged" {
  provider = aws.prod
  user     = aws_iam_user.isadmin_via_group_awsmanaged.name
  groups   = [aws_iam_group.admin_awsmanaged.name]
}

# 5. User in group with customer managed admin policy
resource "aws_iam_user" "isadmin_via_group_customermanaged" {
  provider = aws.prod
  name     = "pl-prod-epe-user-isAdmin-via-group-customermanaged"

  tags = {
    Name        = "pl-prod-epe-user-isAdmin-via-group-customermanaged"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_access_key" "isadmin_via_group_customermanaged" {
  provider = aws.prod
  user     = aws_iam_user.isadmin_via_group_customermanaged.name
}

resource "aws_iam_user_group_membership" "isadmin_via_group_customermanaged" {
  provider = aws.prod
  user     = aws_iam_user.isadmin_via_group_customermanaged.name
  groups   = [aws_iam_group.admin_customermanaged.name]
}

# 6. User in group with inline admin policy
resource "aws_iam_user" "isadmin_via_group_inline" {
  provider = aws.prod
  name     = "pl-prod-epe-user-isAdmin-via-group-inline"

  tags = {
    Name        = "pl-prod-epe-user-isAdmin-via-group-inline"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_access_key" "isadmin_via_group_inline" {
  provider = aws.prod
  user     = aws_iam_user.isadmin_via_group_inline.name
}

resource "aws_iam_user_group_membership" "isadmin_via_group_inline" {
  provider = aws.prod
  user     = aws_iam_user.isadmin_via_group_inline.name
  groups   = [aws_iam_group.admin_inline.name]
}

# =============================================================================
# ISADMIN USERS - MULTI-POLICY (3 users)
# =============================================================================

# 7. User with split IAM and NotIAM policies
resource "aws_iam_user" "isadmin_split_iam_and_notiam" {
  provider = aws.prod
  name     = "pl-prod-epe-user-isAdmin-split-iam-and-notiam"

  tags = {
    Name        = "pl-prod-epe-user-isAdmin-split-iam-and-notiam"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_access_key" "isadmin_split_iam_and_notiam" {
  provider = aws.prod
  user     = aws_iam_user.isadmin_split_iam_and_notiam.name
}

resource "aws_iam_user_policy_attachment" "isadmin_split_iam" {
  provider   = aws.prod
  user       = aws_iam_user.isadmin_split_iam_and_notiam.name
  policy_arn = aws_iam_policy.iam_only_policy.arn
}

resource "aws_iam_user_policy_attachment" "isadmin_split_notiam" {
  provider   = aws.prod
  user       = aws_iam_user.isadmin_split_iam_and_notiam.name
  policy_arn = aws_iam_policy.notaction_iam_policy.arn
}

# 8. User with split S3 and NotS3 policies
resource "aws_iam_user" "isadmin_split_s3_and_nots3" {
  provider = aws.prod
  name     = "pl-prod-epe-user-isAdmin-split-s3-and-nots3"

  tags = {
    Name        = "pl-prod-epe-user-isAdmin-split-s3-and-nots3"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_access_key" "isadmin_split_s3_and_nots3" {
  provider = aws.prod
  user     = aws_iam_user.isadmin_split_s3_and_nots3.name
}

resource "aws_iam_user_policy_attachment" "isadmin_split_s3" {
  provider   = aws.prod
  user       = aws_iam_user.isadmin_split_s3_and_nots3.name
  policy_arn = aws_iam_policy.s3_only_policy.arn
}

resource "aws_iam_user_policy_attachment" "isadmin_split_nots3" {
  provider   = aws.prod
  user       = aws_iam_user.isadmin_split_s3_and_nots3.name
  policy_arn = aws_iam_policy.notaction_s3_policy.arn
}

# 9. User with many services combined
resource "aws_iam_user" "isadmin_many_services_combined" {
  provider = aws.prod
  name     = "pl-prod-epe-user-isAdmin-many-services-combined"

  tags = {
    Name        = "pl-prod-epe-user-isAdmin-many-services-combined"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_access_key" "isadmin_many_services_combined" {
  provider = aws.prod
  user     = aws_iam_user.isadmin_many_services_combined.name
}

resource "aws_iam_user_policy_attachment" "isadmin_many_services" {
  provider   = aws.prod
  user       = aws_iam_user.isadmin_many_services_combined.name
  policy_arn = aws_iam_policy.many_services_policy.arn
}

# =============================================================================
# NOTADMIN USERS - SINGLE DENY (3 users)
# =============================================================================

# 10. User with admin policy + deny all
resource "aws_iam_user" "notadmin_adminpolicy_plus_denyall" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-adminpolicy-plus-denyall"

  tags = {
    Name        = "pl-prod-epe-user-notAdmin-adminpolicy-plus-denyall"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_access_key" "notadmin_adminpolicy_plus_denyall" {
  provider = aws.prod
  user     = aws_iam_user.notadmin_adminpolicy_plus_denyall.name
}

resource "aws_iam_user_policy_attachment" "notadmin_denyall_admin" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_adminpolicy_plus_denyall.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user_policy" "notadmin_denyall" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-denyall-policy"
  user     = aws_iam_user.notadmin_adminpolicy_plus_denyall.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# 11. User with admin policy + deny with NotAction []
resource "aws_iam_user" "notadmin_adminpolicy_plus_denynotaction" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-adminpolicy-plus-denynotaction"

  tags = {
    Name        = "pl-prod-epe-user-notAdmin-adminpolicy-plus-denynotaction"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_access_key" "notadmin_adminpolicy_plus_denynotaction" {
  provider = aws.prod
  user     = aws_iam_user.notadmin_adminpolicy_plus_denynotaction.name
}

resource "aws_iam_user_policy_attachment" "notadmin_denynotaction_admin" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_adminpolicy_plus_denynotaction.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user_policy" "notadmin_denynotaction" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-denynotaction-policy"
  user     = aws_iam_user.notadmin_adminpolicy_plus_denynotaction.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# 12. User with admin policy + deny NotAction [ec2:DescribeInstances]
resource "aws_iam_user" "notadmin_adminpolicy_plus_denynotaction_ec2only" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-admin-plus-denynotaction-ec2only"

  tags = {
    Name        = "pl-prod-epe-user-notAdmin-adminpolicy-plus-denynotaction-ec2only"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_access_key" "notadmin_adminpolicy_plus_denynotaction_ec2only" {
  provider = aws.prod
  user     = aws_iam_user.notadmin_adminpolicy_plus_denynotaction_ec2only.name
}

resource "aws_iam_user_policy_attachment" "notadmin_denynotaction_ec2only_admin" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_adminpolicy_plus_denynotaction_ec2only.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user_policy" "notadmin_denynotaction_ec2only" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-denynotaction-ec2only-policy"
  user     = aws_iam_user.notadmin_adminpolicy_plus_denynotaction_ec2only.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Deny"
        NotAction = ["ec2:DescribeInstances"]
        Resource  = "*"
      }
    ]
  })
}

# =============================================================================
# NOTADMIN USERS - MULTI-DENY (3 users)
# =============================================================================

# 13. User with admin policy + deny split iam/notiam
resource "aws_iam_user" "notadmin_adminpolicy_plus_deny_split_iam_notiam" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-adminpolicy-plus-deny-split-iam-notiam"

  tags = {
    Name        = "pl-prod-epe-user-notAdmin-adminpolicy-plus-deny-split-iam-notiam"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_access_key" "notadmin_adminpolicy_plus_deny_split_iam_notiam" {
  provider = aws.prod
  user     = aws_iam_user.notadmin_adminpolicy_plus_deny_split_iam_notiam.name
}

resource "aws_iam_user_policy_attachment" "notadmin_deny_split_admin" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_adminpolicy_plus_deny_split_iam_notiam.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user_policy" "notadmin_deny_iam" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-deny-iam-policy"
  user     = aws_iam_user.notadmin_adminpolicy_plus_deny_split_iam_notiam.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Deny"
        Action   = "iam:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy" "notadmin_deny_notiam" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-deny-notiam-policy"
  user     = aws_iam_user.notadmin_adminpolicy_plus_deny_split_iam_notiam.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Deny"
        NotAction = ["iam:*"]
        Resource  = "*"
      }
    ]
  })
}

# 14. User with admin policy + deny incremental (multiple denies)
resource "aws_iam_user" "notadmin_adminpolicy_plus_deny_incremental" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-adminpolicy-plus-deny-incremental"

  tags = {
    Name        = "pl-prod-epe-user-notAdmin-adminpolicy-plus-deny-incremental"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_access_key" "notadmin_adminpolicy_plus_deny_incremental" {
  provider = aws.prod
  user     = aws_iam_user.notadmin_adminpolicy_plus_deny_incremental.name
}

resource "aws_iam_user_policy_attachment" "notadmin_deny_incremental_admin" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_adminpolicy_plus_deny_incremental.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user_policy" "notadmin_deny_incremental" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-deny-incremental-policy"
  user     = aws_iam_user.notadmin_adminpolicy_plus_deny_incremental.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Deny", Action = "s3:*", Resource = "*" },
      { Effect = "Deny", Action = "ec2:*", Resource = "*" },
      { Effect = "Deny", Action = "iam:*", Resource = "*" },
      { Effect = "Deny", Action = "lambda:*", Resource = "*" },
      { Effect = "Deny", Action = "cloudwatch:*", Resource = "*" },
      { Effect = "Deny", Action = "logs:*", Resource = "*" },
      { Effect = "Deny", Action = "rds:*", Resource = "*" },
      { Effect = "Deny", Action = "dynamodb:*", Resource = "*" },
      { Effect = "Deny", Action = "sns:*", Resource = "*" },
      { Effect = "Deny", Action = "sqs:*", Resource = "*" },
      { Effect = "Deny", Action = "sts:*", Resource = "*" },
      { Effect = "Deny", Action = "kms:*", Resource = "*" },
      { Effect = "Deny", Action = "apigateway:*", Resource = "*" },
      { Effect = "Deny", Action = "cloudformation:*", Resource = "*" },
      { Effect = "Deny", Action = "elasticloadbalancing:*", Resource = "*" }
    ]
  })
}

# 15. User with split allow + deny all
resource "aws_iam_user" "notadmin_split_allow_plus_denyall" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-split-allow-plus-denyall"

  tags = {
    Name        = "pl-prod-epe-user-notAdmin-split-allow-plus-denyall"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_access_key" "notadmin_split_allow_plus_denyall" {
  provider = aws.prod
  user     = aws_iam_user.notadmin_split_allow_plus_denyall.name
}

resource "aws_iam_user_policy_attachment" "notadmin_split_allow_iam" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_split_allow_plus_denyall.name
  policy_arn = aws_iam_policy.iam_only_policy.arn
}

resource "aws_iam_user_policy_attachment" "notadmin_split_allow_notiam" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_split_allow_plus_denyall.name
  policy_arn = aws_iam_policy.notaction_iam_policy.arn
}

resource "aws_iam_user_policy" "notadmin_split_denyall" {
  provider = aws.prod
  name     = "pl-prod-epe-user-notAdmin-split-denyall-policy"
  user     = aws_iam_user.notadmin_split_allow_plus_denyall.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# NOTADMIN USERS - SINGLE BOUNDARY (3 users)
# =============================================================================

# 16. User with admin policy + boundary allows nothing
resource "aws_iam_user" "notadmin_adminpolicy_plus_boundary_allows_nothing" {
  provider             = aws.prod
  name                 = "pl-prod-epe-user-notAdmin-admin-plus-boundary-allows-nothing"
  permissions_boundary = aws_iam_policy.boundary_allows_nothing.arn

  tags = {
    Name        = "pl-prod-epe-user-notAdmin-adminpolicy-plus-boundary-allows-nothing"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_access_key" "notadmin_adminpolicy_plus_boundary_allows_nothing" {
  provider = aws.prod
  user     = aws_iam_user.notadmin_adminpolicy_plus_boundary_allows_nothing.name
}

resource "aws_iam_user_policy_attachment" "notadmin_boundary_nothing_admin" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_adminpolicy_plus_boundary_allows_nothing.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 17. User with admin policy + boundary ec2only
resource "aws_iam_user" "notadmin_adminpolicy_plus_boundary_ec2only" {
  provider             = aws.prod
  name                 = "pl-prod-epe-user-notAdmin-adminpolicy-plus-boundary-ec2only"
  permissions_boundary = aws_iam_policy.boundary_ec2only.arn

  tags = {
    Name        = "pl-prod-epe-user-notAdmin-adminpolicy-plus-boundary-ec2only"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_access_key" "notadmin_adminpolicy_plus_boundary_ec2only" {
  provider = aws.prod
  user     = aws_iam_user.notadmin_adminpolicy_plus_boundary_ec2only.name
}

resource "aws_iam_user_policy_attachment" "notadmin_boundary_ec2only_admin" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_adminpolicy_plus_boundary_ec2only.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 18. User with admin policy + boundary notaction ec2only
resource "aws_iam_user" "notadmin_adminpolicy_plus_boundary_notaction_ec2only" {
  provider             = aws.prod
  name                 = "pl-prod-epe-user-notAdmin-admin-plus-boundary-na-ec2only"
  permissions_boundary = aws_iam_policy.boundary_notaction_ec2only.arn

  tags = {
    Name        = "pl-prod-epe-user-notAdmin-adminpolicy-plus-boundary-notaction-ec2only"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_access_key" "notadmin_adminpolicy_plus_boundary_notaction_ec2only" {
  provider = aws.prod
  user     = aws_iam_user.notadmin_adminpolicy_plus_boundary_notaction_ec2only.name
}

resource "aws_iam_user_policy_attachment" "notadmin_boundary_notaction_ec2only_admin" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_adminpolicy_plus_boundary_notaction_ec2only.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# =============================================================================
# NOTADMIN USERS - MULTI-POLICY WITH BOUNDARY (3 users)
# =============================================================================

# 19. User with split allow + boundary allows nothing
resource "aws_iam_user" "notadmin_split_allow_boundary_allows_nothing" {
  provider             = aws.prod
  name                 = "pl-prod-epe-user-notAdmin-split-allow-boundary-allows-nothing"
  permissions_boundary = aws_iam_policy.boundary_allows_nothing.arn

  tags = {
    Name        = "pl-prod-epe-user-notAdmin-split-allow-boundary-allows-nothing"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_access_key" "notadmin_split_allow_boundary_allows_nothing" {
  provider = aws.prod
  user     = aws_iam_user.notadmin_split_allow_boundary_allows_nothing.name
}

resource "aws_iam_user_policy_attachment" "notadmin_split_boundary_nothing_iam" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_split_allow_boundary_allows_nothing.name
  policy_arn = aws_iam_policy.iam_only_policy.arn
}

resource "aws_iam_user_policy_attachment" "notadmin_split_boundary_nothing_notiam" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_split_allow_boundary_allows_nothing.name
  policy_arn = aws_iam_policy.notaction_iam_policy.arn
}

# 20. User with split allow + boundary ec2only
resource "aws_iam_user" "notadmin_split_allow_boundary_ec2only" {
  provider             = aws.prod
  name                 = "pl-prod-epe-user-notAdmin-split-allow-boundary-ec2only"
  permissions_boundary = aws_iam_policy.boundary_ec2only.arn

  tags = {
    Name        = "pl-prod-epe-user-notAdmin-split-allow-boundary-ec2only"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_access_key" "notadmin_split_allow_boundary_ec2only" {
  provider = aws.prod
  user     = aws_iam_user.notadmin_split_allow_boundary_ec2only.name
}

resource "aws_iam_user_policy_attachment" "notadmin_split_boundary_ec2_iam" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_split_allow_boundary_ec2only.name
  policy_arn = aws_iam_policy.iam_only_policy.arn
}

resource "aws_iam_user_policy_attachment" "notadmin_split_boundary_ec2_notiam" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_split_allow_boundary_ec2only.name
  policy_arn = aws_iam_policy.notaction_iam_policy.arn
}

# 21. User with split boundary mismatch
resource "aws_iam_user" "notadmin_split_boundary_mismatch" {
  provider             = aws.prod
  name                 = "pl-prod-epe-user-notAdmin-split-boundary-mismatch"
  permissions_boundary = aws_iam_policy.boundary_iam_only.arn

  tags = {
    Name        = "pl-prod-epe-user-notAdmin-split-boundary-mismatch"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_access_key" "notadmin_split_boundary_mismatch" {
  provider = aws.prod
  user     = aws_iam_user.notadmin_split_boundary_mismatch.name
}

resource "aws_iam_user_policy_attachment" "notadmin_boundary_mismatch" {
  provider   = aws.prod
  user       = aws_iam_user.notadmin_split_boundary_mismatch.name
  policy_arn = aws_iam_policy.notaction_iam_policy.arn
}

# =============================================================================
# ISADMIN ROLES - SINGLE POLICY (3 roles)
# =============================================================================

# 22. Role with AWS managed admin policy
resource "aws_iam_role" "isadmin_awsmanaged" {
  provider = aws.prod
  name     = "pl-prod-epe-role-isAdmin-awsmanaged"

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
    Name        = "pl-prod-epe-role-isAdmin-awsmanaged"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_role_policy_attachment" "isadmin_role_awsmanaged" {
  provider   = aws.prod
  role       = aws_iam_role.isadmin_awsmanaged.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 23. Role with customer managed admin policy
resource "aws_iam_role" "isadmin_customermanaged" {
  provider = aws.prod
  name     = "pl-prod-epe-role-isAdmin-customermanaged"

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
    Name        = "pl-prod-epe-role-isAdmin-customermanaged"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_role_policy_attachment" "isadmin_role_customermanaged" {
  provider   = aws.prod
  role       = aws_iam_role.isadmin_customermanaged.name
  policy_arn = aws_iam_policy.admin_customer_policy.arn
}

# 24. Role with inline admin policy
resource "aws_iam_role" "isadmin_inline" {
  provider = aws.prod
  name     = "pl-prod-epe-role-isAdmin-inline"

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
    Name        = "pl-prod-epe-role-isAdmin-inline"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_role_policy" "isadmin_role_inline" {
  provider = aws.prod
  name     = "pl-prod-epe-role-isAdmin-inline-policy"
  role     = aws_iam_role.isadmin_inline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# ISADMIN ROLES - MULTI-POLICY (3 roles)
# =============================================================================

# 25. Role with split IAM and NotIAM policies
resource "aws_iam_role" "isadmin_split_iam_and_notiam" {
  provider = aws.prod
  name     = "pl-prod-epe-role-isAdmin-split-iam-and-notiam"

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
    Name        = "pl-prod-epe-role-isAdmin-split-iam-and-notiam"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_role_policy_attachment" "isadmin_role_split_iam" {
  provider   = aws.prod
  role       = aws_iam_role.isadmin_split_iam_and_notiam.name
  policy_arn = aws_iam_policy.iam_only_policy.arn
}

resource "aws_iam_role_policy_attachment" "isadmin_role_split_notiam" {
  provider   = aws.prod
  role       = aws_iam_role.isadmin_split_iam_and_notiam.name
  policy_arn = aws_iam_policy.notaction_iam_policy.arn
}

# 26. Role with split S3 and NotS3 policies
resource "aws_iam_role" "isadmin_split_s3_and_nots3" {
  provider = aws.prod
  name     = "pl-prod-epe-role-isAdmin-split-s3-and-nots3"

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
    Name        = "pl-prod-epe-role-isAdmin-split-s3-and-nots3"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_role_policy_attachment" "isadmin_role_split_s3" {
  provider   = aws.prod
  role       = aws_iam_role.isadmin_split_s3_and_nots3.name
  policy_arn = aws_iam_policy.s3_only_policy.arn
}

resource "aws_iam_role_policy_attachment" "isadmin_role_split_nots3" {
  provider   = aws.prod
  role       = aws_iam_role.isadmin_split_s3_and_nots3.name
  policy_arn = aws_iam_policy.notaction_s3_policy.arn
}

# 27. Role with many services combined
resource "aws_iam_role" "isadmin_many_services_combined" {
  provider = aws.prod
  name     = "pl-prod-epe-role-isAdmin-many-services-combined"

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
    Name        = "pl-prod-epe-role-isAdmin-many-services-combined"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "admin"
  }
}

resource "aws_iam_role_policy_attachment" "isadmin_role_many_services" {
  provider   = aws.prod
  role       = aws_iam_role.isadmin_many_services_combined.name
  policy_arn = aws_iam_policy.many_services_policy.arn
}

# =============================================================================
# NOTADMIN ROLES - SINGLE DENY (3 roles)
# =============================================================================

# 28. Role with admin policy + deny all
resource "aws_iam_role" "notadmin_adminpolicy_plus_denyall" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-adminpolicy-plus-denyall"

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
    Name        = "pl-prod-epe-role-notAdmin-adminpolicy-plus-denyall"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_role_policy_attachment" "notadmin_role_denyall_admin" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_adminpolicy_plus_denyall.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "notadmin_role_denyall" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-denyall-policy"
  role     = aws_iam_role.notadmin_adminpolicy_plus_denyall.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# 29. Role with admin policy + deny with NotAction []
resource "aws_iam_role" "notadmin_adminpolicy_plus_denynotaction" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-adminpolicy-plus-denynotaction"

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
    Name        = "pl-prod-epe-role-notAdmin-adminpolicy-plus-denynotaction"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_role_policy_attachment" "notadmin_role_denynotaction_admin" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_adminpolicy_plus_denynotaction.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "notadmin_role_denynotaction" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-denynotaction-policy"
  role     = aws_iam_role.notadmin_adminpolicy_plus_denynotaction.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# 30. Role with admin policy + deny NotAction [ec2:DescribeInstances]
resource "aws_iam_role" "notadmin_adminpolicy_plus_denynotaction_ec2only" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-adminpolicy-plus-denynotaction-ec2only"

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
    Name        = "pl-prod-epe-role-notAdmin-adminpolicy-plus-denynotaction-ec2only"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_role_policy_attachment" "notadmin_role_denynotaction_ec2only_admin" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_adminpolicy_plus_denynotaction_ec2only.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "notadmin_role_denynotaction_ec2only" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-denynotaction-ec2only-policy"
  role     = aws_iam_role.notadmin_adminpolicy_plus_denynotaction_ec2only.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Deny"
        NotAction = ["ec2:DescribeInstances"]
        Resource  = "*"
      }
    ]
  })
}

# =============================================================================
# NOTADMIN ROLES - MULTI-DENY (3 roles)
# =============================================================================

# 31. Role with admin policy + deny split iam/notiam
resource "aws_iam_role" "notadmin_adminpolicy_plus_deny_split_iam_notiam" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-adminpolicy-plus-deny-split-iam-notiam"

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
    Name        = "pl-prod-epe-role-notAdmin-adminpolicy-plus-deny-split-iam-notiam"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_role_policy_attachment" "notadmin_role_deny_split_admin" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_adminpolicy_plus_deny_split_iam_notiam.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "notadmin_role_deny_iam" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-deny-iam-policy"
  role     = aws_iam_role.notadmin_adminpolicy_plus_deny_split_iam_notiam.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Deny"
        Action   = "iam:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "notadmin_role_deny_notiam" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-deny-notiam-policy"
  role     = aws_iam_role.notadmin_adminpolicy_plus_deny_split_iam_notiam.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Deny"
        NotAction = ["iam:*"]
        Resource  = "*"
      }
    ]
  })
}

# 32. Role with admin policy + deny incremental (multiple denies)
resource "aws_iam_role" "notadmin_adminpolicy_plus_deny_incremental" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-adminpolicy-plus-deny-incremental"

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
    Name        = "pl-prod-epe-role-notAdmin-adminpolicy-plus-deny-incremental"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_role_policy_attachment" "notadmin_role_deny_incremental_admin" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_adminpolicy_plus_deny_incremental.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "notadmin_role_deny_incremental" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-deny-incremental-policy"
  role     = aws_iam_role.notadmin_adminpolicy_plus_deny_incremental.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Deny", Action = "s3:*", Resource = "*" },
      { Effect = "Deny", Action = "ec2:*", Resource = "*" },
      { Effect = "Deny", Action = "iam:*", Resource = "*" },
      { Effect = "Deny", Action = "lambda:*", Resource = "*" },
      { Effect = "Deny", Action = "cloudwatch:*", Resource = "*" },
      { Effect = "Deny", Action = "logs:*", Resource = "*" },
      { Effect = "Deny", Action = "rds:*", Resource = "*" },
      { Effect = "Deny", Action = "dynamodb:*", Resource = "*" },
      { Effect = "Deny", Action = "sns:*", Resource = "*" },
      { Effect = "Deny", Action = "sqs:*", Resource = "*" },
      { Effect = "Deny", Action = "sts:*", Resource = "*" },
      { Effect = "Deny", Action = "kms:*", Resource = "*" },
      { Effect = "Deny", Action = "apigateway:*", Resource = "*" },
      { Effect = "Deny", Action = "cloudformation:*", Resource = "*" },
      { Effect = "Deny", Action = "elasticloadbalancing:*", Resource = "*" }
    ]
  })
}

# 33. Role with split allow + deny all
resource "aws_iam_role" "notadmin_split_allow_plus_denyall" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-split-allow-plus-denyall"

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
    Name        = "pl-prod-epe-role-notAdmin-split-allow-plus-denyall"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_role_policy_attachment" "notadmin_role_split_allow_iam" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_split_allow_plus_denyall.name
  policy_arn = aws_iam_policy.iam_only_policy.arn
}

resource "aws_iam_role_policy_attachment" "notadmin_role_split_allow_notiam" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_split_allow_plus_denyall.name
  policy_arn = aws_iam_policy.notaction_iam_policy.arn
}

resource "aws_iam_role_policy" "notadmin_role_split_denyall" {
  provider = aws.prod
  name     = "pl-prod-epe-role-notAdmin-split-denyall-policy"
  role     = aws_iam_role.notadmin_split_allow_plus_denyall.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# NOTADMIN ROLES - SINGLE BOUNDARY (3 roles)
# =============================================================================

# 34. Role with admin policy + boundary allows nothing
resource "aws_iam_role" "notadmin_adminpolicy_plus_boundary_allows_nothing" {
  provider             = aws.prod
  name                 = "pl-prod-epe-role-notAdmin-admin-plus-boundary-allows-nothing"
  permissions_boundary = aws_iam_policy.boundary_allows_nothing.arn

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
    Name        = "pl-prod-epe-role-notAdmin-adminpolicy-plus-boundary-allows-nothing"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_role_policy_attachment" "notadmin_role_boundary_nothing_admin" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_adminpolicy_plus_boundary_allows_nothing.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 35. Role with admin policy + boundary ec2only
resource "aws_iam_role" "notadmin_adminpolicy_plus_boundary_ec2only" {
  provider             = aws.prod
  name                 = "pl-prod-epe-role-notAdmin-adminpolicy-plus-boundary-ec2only"
  permissions_boundary = aws_iam_policy.boundary_ec2only.arn

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
    Name        = "pl-prod-epe-role-notAdmin-adminpolicy-plus-boundary-ec2only"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_role_policy_attachment" "notadmin_role_boundary_ec2only_admin" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_adminpolicy_plus_boundary_ec2only.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 36. Role with admin policy + boundary notaction ec2only
resource "aws_iam_role" "notadmin_adminpolicy_plus_boundary_notaction_ec2only" {
  provider             = aws.prod
  name                 = "pl-prod-epe-role-notAdmin-admin-plus-boundary-na-ec2only"
  permissions_boundary = aws_iam_policy.boundary_notaction_ec2only.arn

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
    Name        = "pl-prod-epe-role-notAdmin-adminpolicy-plus-boundary-notaction-ec2only"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_role_policy_attachment" "notadmin_role_boundary_notaction_ec2only_admin" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_adminpolicy_plus_boundary_notaction_ec2only.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# =============================================================================
# NOTADMIN ROLES - MULTI-POLICY WITH BOUNDARY (3 roles)
# =============================================================================

# 37. Role with split allow + boundary allows nothing
resource "aws_iam_role" "notadmin_split_allow_boundary_allows_nothing" {
  provider             = aws.prod
  name                 = "pl-prod-epe-role-notAdmin-split-allow-boundary-allows-nothing"
  permissions_boundary = aws_iam_policy.boundary_allows_nothing.arn

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
    Name        = "pl-prod-epe-role-notAdmin-split-allow-boundary-allows-nothing"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_role_policy_attachment" "notadmin_role_split_boundary_nothing_iam" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_split_allow_boundary_allows_nothing.name
  policy_arn = aws_iam_policy.iam_only_policy.arn
}

resource "aws_iam_role_policy_attachment" "notadmin_role_split_boundary_nothing_notiam" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_split_allow_boundary_allows_nothing.name
  policy_arn = aws_iam_policy.notaction_iam_policy.arn
}

# 38. Role with split allow + boundary ec2only
resource "aws_iam_role" "notadmin_split_allow_boundary_ec2only" {
  provider             = aws.prod
  name                 = "pl-prod-epe-role-notAdmin-split-allow-boundary-ec2only"
  permissions_boundary = aws_iam_policy.boundary_ec2only.arn

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
    Name        = "pl-prod-epe-role-notAdmin-split-allow-boundary-ec2only"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_role_policy_attachment" "notadmin_role_split_boundary_ec2_iam" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_split_allow_boundary_ec2only.name
  policy_arn = aws_iam_policy.iam_only_policy.arn
}

resource "aws_iam_role_policy_attachment" "notadmin_role_split_boundary_ec2_notiam" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_split_allow_boundary_ec2only.name
  policy_arn = aws_iam_policy.notaction_iam_policy.arn
}

# 39. Role with split boundary mismatch
resource "aws_iam_role" "notadmin_split_boundary_mismatch" {
  provider             = aws.prod
  name                 = "pl-prod-epe-role-notAdmin-split-boundary-mismatch"
  permissions_boundary = aws_iam_policy.boundary_iam_only.arn

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
    Name        = "pl-prod-epe-role-notAdmin-split-boundary-mismatch"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
    TestResult  = "not-admin"
  }
}

resource "aws_iam_role_policy_attachment" "notadmin_role_boundary_mismatch" {
  provider   = aws.prod
  role       = aws_iam_role.notadmin_split_boundary_mismatch.name
  policy_arn = aws_iam_policy.notaction_iam_policy.arn
}

# =============================================================================
# S3 BUCKET
# =============================================================================

resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-sensitive-data-epe-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-sensitive-data-epe-bucket"
    Environment = var.environment
    Scenario    = "test-effective-permissions-evaluation"
  }
}

resource "aws_s3_bucket_public_access_block" "target_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is sensitive data for testing effective permissions evaluation."
}
