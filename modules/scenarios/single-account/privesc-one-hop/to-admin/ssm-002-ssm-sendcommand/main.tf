terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# SSM SendCommand privilege escalation scenario
#
# This scenario demonstrates how a user with ssm:SendCommand permission can execute
# commands on an EC2 instance that has an admin role attached, extract the instance's
# temporary credentials from the metadata endpoint, and gain admin access.

# Resource naming convention: pl-prod-ssm-002-to-admin-{resource-type}

# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Get the latest Amazon Linux 2 AMI (has SSM agent pre-installed)
data "aws_ami" "amazon_linux_2" {
  provider    = aws.prod
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get default VPC for simplicity
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

# ==============================================================================
# SCENARIO-SPECIFIC STARTING USER
# ==============================================================================

resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ssm-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ssm-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "ssm-sendcommand"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting SSM permissions to the starting user
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-ssm-002-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  # Ensure the EC2 instance is created before the policy references it
  depends_on = [aws_instance.target]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BasicIdentityPermissions"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:GetUser"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMSendCommandForPrivesc"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand"
        ]
        Resource = [
          aws_instance.target.arn,
          "arn:aws:ssm:*:*:document/AWS-RunShellScript"
        ]
      },
      {
        Sid    = "SSMHelpfulForDemo"
        Effect = "Allow"
        Action = [
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# EC2 ADMIN ROLE (TARGET)
# ==============================================================================

# Admin role that will be attached to the EC2 instance
resource "aws_iam_role" "ec2_admin" {
  provider = aws.prod
  name     = "pl-prod-ssm-002-to-admin-ec2-admin-role"

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
    Name        = "pl-prod-ssm-002-to-admin-ec2-admin-role"
    Environment = var.environment
    Scenario    = "ssm-sendcommand"
    Purpose     = "ec2-admin-role"
  }
}

# Attach AdministratorAccess policy to the EC2 role (target privilege level)
resource "aws_iam_role_policy_attachment" "ec2_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.ec2_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Attach SSM managed instance core policy (required for SSM agent to work)
resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  provider   = aws.prod
  role       = aws_iam_role.ec2_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile to link the role to EC2
resource "aws_iam_instance_profile" "ec2_admin" {
  provider = aws.prod
  name     = "pl-prod-ssm-002-to-admin-instance-profile"
  role     = aws_iam_role.ec2_admin.name

  tags = {
    Name        = "pl-prod-ssm-002-to-admin-instance-profile"
    Environment = var.environment
    Scenario    = "ssm-sendcommand"
    Purpose     = "instance-profile"
  }
}

# ==============================================================================
# EC2 TARGET INSTANCE
# ==============================================================================

# Security group allowing outbound traffic (needed for SSM to work)
resource "aws_security_group" "target_instance" {
  provider    = aws.prod
  name        = "pl-prod-ssm-002-to-admin-sg"
  description = "Security group for SSM SendCommand scenario target instance"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic for SSM connectivity"
  }

  tags = {
    Name        = "pl-prod-ssm-002-to-admin-sg"
    Environment = var.environment
    Scenario    = "ssm-sendcommand"
    Purpose     = "security-group"
  }
}

# EC2 instance with admin role attached
resource "aws_instance" "target" {
  provider             = aws.prod
  ami                  = data.aws_ami.amazon_linux_2.id
  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_admin.name
  subnet_id            = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids = [
    aws_security_group.target_instance.id
  ]

  # Public IP needed for SSM connectivity (unless VPC endpoints are configured)
  associate_public_ip_address = true

  tags = {
    Name        = "pl-prod-ssm-002-to-admin-target-instance"
    Environment = var.environment
    Scenario    = "ssm-sendcommand"
    Purpose     = "target-instance"
  }
}
