terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

#  EC2 Instance with Highly Privileged IAM Role
#
# This scenario creates an EC2 instance with an administrative IAM role attached.
# This is a common CSPM detection: EC2 instances should not have highly privileged
# IAM roles attached, as anyone with access to the instance can leverage those
# permissions.
#
# Detection: aws-ec2-instance-ec2-instance-should-not-have-a-highly-privileged-iam-role-attached-to-it

# Resource naming convention: pl-cspm-ec2-001-{resource-type}

# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Get the latest Amazon Linux 2023 AMI (has SSM agent pre-installed)
data "aws_ami" "amazon_linux_2023" {
  provider    = aws.prod
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get default VPC for simplicity
# Get default subnets
# ==============================================================================
# EC2 ADMIN ROLE (THE MISCONFIGURATION)
# ==============================================================================

# Admin role attached to the EC2 instance - this is what CSPM should detect
resource "aws_iam_role" "ec2_admin" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-cspm-ec2-001-admin-role"

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
    Name        = "pl-cspm-ec2-001-admin-role"
    Environment = var.environment
    Scenario    = "cspm-ec2-001"
    Purpose     = "ec2-admin-role"
    CSPMCheck   = "ec2-instance-should-not-have-a-highly-privileged-iam-role"
  }
}

# Attach AdministratorAccess policy - THE MISCONFIGURATION
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
  name     = "pl-cspm-ec2-001-instance-profile"
  role     = aws_iam_role.ec2_admin.name

  tags = {
    Name        = "pl-cspm-ec2-001-instance-profile"
    Environment = var.environment
    Scenario    = "cspm-ec2-001"
    Purpose     = "instance-profile"
  }
}

# ==============================================================================
# EC2 INSTANCE
# ==============================================================================

# Security group allowing outbound traffic (needed for SSM to work)
resource "aws_security_group" "instance" {
  provider    = aws.prod
  name        = "pl-cspm-ec2-001-sg"
  description = "Security group for CSPM EC2 privileged role scenario"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic for SSM connectivity"
  }

  tags = {
    Name        = "pl-cspm-ec2-001-sg"
    Environment = var.environment
    Scenario    = "cspm-ec2-001"
    Purpose     = "security-group"
  }
}

# EC2 instance with admin role attached - THE MISCONFIGURATION
resource "aws_instance" "target" {
  provider             = aws.prod
  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = "t3.nano"
  iam_instance_profile = aws_iam_instance_profile.ec2_admin.name
  subnet_id            = var.subnet_id
  vpc_security_group_ids = [
    aws_security_group.instance.id
  ]

  # Public IP needed for SSM connectivity (unless VPC endpoints are configured)
  associate_public_ip_address = true

  tags = {
    Name        = "pl-cspm-ec2-001-instance"
    Environment = var.environment
    Scenario    = "cspm-ec2-001"
    Purpose     = "misconfigured-instance"
    CSPMCheck   = "ec2-instance-should-not-have-a-highly-privileged-iam-role"
  }
}

# ==============================================================================
# DEMO USER (for demonstrating the risk)
# ==============================================================================

# User with SSM access - represents anyone who could access the instance
resource "aws_iam_user" "demo_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-cspm-ec2-001-demo-user"

  tags = {
    Name        = "pl-cspm-ec2-001-demo-user"
    Environment = var.environment
    Scenario    = "cspm-ec2-001"
    Purpose     = "demo-user"
  }
}

# Create access keys for the demo user
resource "aws_iam_access_key" "demo_user" {
  provider = aws.prod
  user     = aws_iam_user.demo_user.name
}

# Policy granting SSM StartSession permissions to demonstrate the risk
resource "aws_iam_user_policy" "demo_user_policy" {
  provider = aws.prod
  name     = "pl-cspm-ec2-001-demo-user-policy"
  user     = aws_iam_user.demo_user.name

  # Ensure the EC2 instance is created before the policy references it
  depends_on = [aws_instance.target]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationSSMStartSession"
        Effect = "Allow"
        Action = [
          "ssm:StartSession"
        ]
        Resource = [
          aws_instance.target.arn,
          "arn:aws:ssm:*:*:document/SSM-SessionManagerRunShell"
        ]
      },
      {
        Sid    = "RequiredForExploitationSSMTerminateSession"
        Effect = "Allow"
        Action = [
          "ssm:TerminateSession"
        ]
        Resource = "arn:aws:ssm:*:*:session/*"
      }
    ]
  })
}

# ==============================================================================
# CTF FLAG
# ==============================================================================

# The flag is stored in SSM Parameter Store and is readable by any admin-equivalent
# principal. In this scenario, the attacker extracts temporary credentials from the
# EC2 instance metadata service (IMDS) via an SSM session. Those credentials belong
# to the instance's admin role (AdministratorAccess), which implicitly grants
# ssm:GetParameter. The attacker uses the stolen credentials to read the flag.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/cspm-ec2-001-to-admin"
  description = "CTF flag for the cspm-ec2-001 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-cspm-ec2-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "cspm-ec2-001"
    Purpose     = "ctf-flag"
  }
}
