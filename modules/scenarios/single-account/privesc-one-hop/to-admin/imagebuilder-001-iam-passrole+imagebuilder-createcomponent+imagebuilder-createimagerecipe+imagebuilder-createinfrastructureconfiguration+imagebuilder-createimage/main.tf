# PassRole + EC2 Image Builder privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and EC2 Image Builder
# permissions can escalate privileges by:
# 1. Creating a component with malicious shell commands
# 2. Creating an image recipe referencing the malicious component
# 3. Creating an infrastructure configuration that passes an admin instance profile
# 4. Creating an image that launches an EC2 build instance running the component
# 5. The build instance executes shell commands with admin role credentials via IMDS
# 6. Those commands attach AdministratorAccess to the starting user
#
# Cost: $0/mo at rest (IAM user, role, and instance profile only - no compute)
# Build time: 10-30+ minutes per image build

# Resource naming convention: pl-prod-imagebuilder-001-to-admin-{resource-type}
# imagebuilder-001 = pathfinding.cloud ID for this scenario

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-imagebuilder-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-imagebuilder-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+imagebuilder-createcomponent+imagebuilder-createimagerecipe+imagebuilder-createinfrastructureconfiguration+imagebuilder-createimage"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Permissions policy for the starting user
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-imagebuilder-001-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.admin_role.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Sid    = "RequiredForExploitationImageBuilder"
        Effect = "Allow"
        Action = [
          "imagebuilder:CreateComponent",
          "imagebuilder:CreateImageRecipe",
          "imagebuilder:CreateInfrastructureConfiguration",
          "imagebuilder:CreateImage"
        ]
        Resource = "*"
      },
      {
        # The Image Builder Create* APIs have dependent actions enforced server-side.
        # CreateImageRecipe requires: GetComponent, GetImage, ec2:DescribeImages
        # CreateImage requires: GetImageRecipe, GetInfrastructureConfiguration
        # All Create* actions require: TagResource
        # See: https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonec2imagebuilder.html
        Sid    = "RequiredForExploitationImageBuilderDependentActions"
        Effect = "Allow"
        Action = [
          "imagebuilder:GetComponent",
          "imagebuilder:GetImage",
          "imagebuilder:GetImageRecipe",
          "imagebuilder:GetInfrastructureConfiguration",
          "imagebuilder:TagResource",
          "ec2:DescribeImages"
        ]
        Resource = "*"
      },
      {
        # Helpful permissions: used for observation and monitoring during the demo.
        # These are temporarily denied by demo_permissions.sh during validation runs
        # to confirm only the Required permissions above are needed for the attack.
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "imagebuilder:ListImages",
          "iam:ListAttachedUserPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ADMIN ROLE + INSTANCE PROFILE (Privilege Escalation Target)
# =============================================================================

# Admin role that will be passed via an instance profile to the EC2 Image Builder
# build instance. The role trusts ec2.amazonaws.com because Image Builder launches
# an EC2 instance that assumes this role via the instance metadata service (IMDS).
resource "aws_iam_role" "admin_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-imagebuilder-001-to-admin-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-imagebuilder-001-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+imagebuilder-createcomponent+imagebuilder-createimagerecipe+imagebuilder-createinfrastructureconfiguration+imagebuilder-createimage"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess policy to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Security group for the Image Builder build instance - allows outbound only
resource "aws_security_group" "build_instance" {
  provider    = aws.prod
  name        = "pl-prod-imagebuilder-001-to-admin-build-sg"
  description = "Security group for Image Builder build instance - egress only"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (needed for SSM agent, IMDS, and AWS API calls)"
  }

  tags = {
    Name        = "pl-prod-imagebuilder-001-to-admin-build-sg"
    Environment = var.environment
    Scenario    = "iam-passrole+imagebuilder-createcomponent+imagebuilder-createimagerecipe+imagebuilder-createinfrastructureconfiguration+imagebuilder-createimage"
    Purpose     = "build-instance-security-group"
  }
}

# CTF flag stored in SSM Parameter Store. Retrieved by the attacker once they reach
# administrator-equivalent permissions. AdministratorAccess grants ssm:GetParameter
# implicitly, so no extra IAM wiring is needed beyond the admin access gained from
# this scenario's privilege escalation path.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/imagebuilder-001-to-admin"
  description = "CTF flag for the imagebuilder-001 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-imagebuilder-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+imagebuilder-createcomponent+imagebuilder-createimagerecipe+imagebuilder-createinfrastructureconfiguration+imagebuilder-createimage"
    Purpose     = "ctf-flag"
  }
}

# Instance profile for the admin role - Image Builder uses this (not the role ARN directly)
resource "aws_iam_instance_profile" "admin_profile" {
  provider = aws.prod
  name     = "pl-prod-imagebuilder-001-to-admin-admin-profile"
  role     = aws_iam_role.admin_role.name

  tags = {
    Name        = "pl-prod-imagebuilder-001-to-admin-admin-profile"
    Environment = var.environment
    Scenario    = "iam-passrole+imagebuilder-createcomponent+imagebuilder-createimagerecipe+imagebuilder-createinfrastructureconfiguration+imagebuilder-createimage"
    Purpose     = "admin-instance-profile"
  }
}
