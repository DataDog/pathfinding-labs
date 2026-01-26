# Launch Template Modification privilege escalation scenario
#
# This scenario demonstrates how a user with CreateLaunchTemplateVersion and
# ModifyLaunchTemplate permissions can escalate privileges by modifying an existing
# launch template to use an admin role that already exists in the template.
# When instances launch from the modified template, user data can grant admin access to the attacker.

# Resource naming convention: pl-prod-ec2-005-to-admin-{resource-type}

# =============================================================================
# STARTING USER (ATTACKER)
# =============================================================================

resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ec2-005-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ec2-005-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting required and helpful permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-ec2-005-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "requiredPermissions"
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplateVersion",
          "ec2:ModifyLaunchTemplate"
        ]
        Resource = "*"
      },
      {
        Sid    = "helpfulAdditionalPermissions"
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "autoscaling:DescribeAutoScalingGroups",
          "ec2:DescribeInstances",
          "autoscaling:SetDesiredCapacity"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# LOW-PRIVILEGE ROLE (ORIGINAL TEMPLATE ROLE)
# =============================================================================

resource "aws_iam_role" "lowpriv_role" {
  provider = aws.prod
  name     = "pl-prod-ec2-005-to-admin-lowpriv-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-ec2-005-to-admin-lowpriv-role"
    Environment = var.environment
    Scenario    = "ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate"
    Purpose     = "lowpriv-role"
  }
}

# Minimal permissions for low-priv role
resource "aws_iam_role_policy" "lowpriv_role_policy" {
  provider = aws.prod
  name     = "pl-prod-ec2-005-to-admin-lowpriv-policy"
  role     = aws_iam_role.lowpriv_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance profile for low-priv role
resource "aws_iam_instance_profile" "lowpriv_profile" {
  provider = aws.prod
  name     = "pl-prod-ec2-005-to-admin-lowpriv-profile"
  role     = aws_iam_role.lowpriv_role.name

  tags = {
    Name        = "pl-prod-ec2-005-to-admin-lowpriv-profile"
    Environment = var.environment
    Scenario    = "ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate"
  }
}

# =============================================================================
# TARGET ADMIN ROLE
# =============================================================================

resource "aws_iam_role" "target_admin_role" {
  provider = aws.prod
  name     = "pl-prod-ec2-005-to-admin-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-ec2-005-to-admin-target-role"
    Environment = var.environment
    Scenario    = "ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to target role
resource "aws_iam_role_policy_attachment" "target_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Instance profile for target admin role
resource "aws_iam_instance_profile" "target_admin_profile" {
  provider = aws.prod
  name     = "pl-prod-ec2-005-to-admin-target-profile"
  role     = aws_iam_role.target_admin_role.name

  tags = {
    Name        = "pl-prod-ec2-005-to-admin-target-profile"
    Environment = var.environment
    Scenario    = "ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate"
  }
}

# =============================================================================
# VICTIM INFRASTRUCTURE
# =============================================================================

# Get the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  provider    = aws.prod
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get default VPC
data "aws_vpc" "default" {
  provider = aws.prod
  default  = true
}

# Get default subnets
data "aws_subnets" "default" {
  provider = aws.prod
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group for instances (minimal access)
resource "aws_security_group" "victim_sg" {
  provider    = aws.prod
  name        = "pl-prod-ec2-005-to-admin-victim-sg"
  description = "Security group for victim launch template instances"
  vpc_id      = data.aws_vpc.default.id

  # Allow outbound traffic for user data execution
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "pl-prod-ec2-005-to-admin-victim-sg"
    Environment = var.environment
    Scenario    = "ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate"
  }
}

# Victim launch template with low-priv role
resource "aws_launch_template" "victim_template" {
  provider      = aws.prod
  name          = "pl-prod-ec2-005-to-admin-victim-template"
  description   = "Victim launch template that will be modified for privilege escalation"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"

  iam_instance_profile {
    arn = aws_iam_instance_profile.lowpriv_profile.arn
  }

  vpc_security_group_ids = [aws_security_group.victim_sg.id]

  # Spot instance configuration for cost savings
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price          = "0.02"
      spot_instance_type = "one-time"
    }
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Original benign user data
    echo "Instance launched with low-privilege role"
    echo "Launch time: $(date)" > /tmp/launch-info.txt
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "pl-prod-ec2-005-to-admin-victim-instance"
      Environment = var.environment
      Scenario    = "ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate"
    }
  }

  tags = {
    Name        = "pl-prod-ec2-005-to-admin-victim-template"
    Environment = var.environment
    Scenario    = "ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate"
    Purpose     = "victim-launch-template"
  }
}

# Victim Auto Scaling Group using the launch template
resource "aws_autoscaling_group" "victim_asg" {
  provider            = aws.prod
  name                = "pl-prod-ec2-005-to-admin-victim-asg"
  vpc_zone_identifier = data.aws_subnets.default.ids
  desired_capacity    = 0
  max_size            = 2
  min_size            = 0

  launch_template {
    id      = aws_launch_template.victim_template.id
    version = "$Default"
  }

  tag {
    key                 = "Name"
    value               = "pl-prod-ec2-005-to-admin-victim-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = false
  }

  tag {
    key                 = "Scenario"
    value               = "ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate"
    propagate_at_launch = false
  }

  tag {
    key                 = "Purpose"
    value               = "victim-asg"
    propagate_at_launch = false
  }
}
