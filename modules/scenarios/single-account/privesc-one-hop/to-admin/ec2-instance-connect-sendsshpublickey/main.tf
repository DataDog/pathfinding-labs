terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# EC2 Instance Connect SendSSHPublicKey privilege escalation scenario
#
# This scenario demonstrates how a user with ec2-instance-connect:SendSSHPublicKey
# permission can push a temporary SSH public key to an EC2 instance, SSH into it,
# and extract the instance's IAM role credentials from the metadata endpoint to
# gain admin access.

# Resource naming convention: pl-prod-eic-to-admin-{resource-type}

# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Get the latest Amazon Linux 2023 AMI (has EC2 Instance Connect pre-configured)
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

# Get the current user's public IP address
data "http" "user_public_ip" {
  url = "https://checkip.amazonaws.com"
}

# ==============================================================================
# SCENARIO-SPECIFIC STARTING USER
# ==============================================================================

resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-eic-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-eic-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "ec2-instance-connect-sendsshpublickey"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting EC2 Instance Connect permissions to the starting user
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-eic-to-admin-starting-user-policy"
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
        Sid    = "EC2InstanceConnectForPrivesc"
        Effect = "Allow"
        Action = [
          "ec2-instance-connect:SendSSHPublicKey"
        ]
        Resource = aws_instance.target.arn
      },
      {
        Sid    = "HelpfulPermissionsForDemo"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "iam:GetInstanceProfile",
          "iam:GetRole"
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
  name     = "pl-prod-eic-to-admin-ec2-admin-role"

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
    Name        = "pl-prod-eic-to-admin-ec2-admin-role"
    Environment = var.environment
    Scenario    = "ec2-instance-connect-sendsshpublickey"
    Purpose     = "ec2-admin-role"
  }
}

# Attach AdministratorAccess policy to the EC2 role (target privilege level)
resource "aws_iam_role_policy_attachment" "ec2_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.ec2_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Instance profile to link the role to EC2
resource "aws_iam_instance_profile" "ec2_admin" {
  provider = aws.prod
  name     = "pl-prod-eic-to-admin-instance-profile"
  role     = aws_iam_role.ec2_admin.name

  tags = {
    Name        = "pl-prod-eic-to-admin-instance-profile"
    Environment = var.environment
    Scenario    = "ec2-instance-connect-sendsshpublickey"
    Purpose     = "instance-profile"
  }
}

# ==============================================================================
# EC2 TARGET INSTANCE
# ==============================================================================

# Security group allowing SSH from anywhere (for EC2 Instance Connect)
resource "aws_security_group" "target_instance" {
  provider    = aws.prod
  name        = "pl-prod-eic-to-admin-sg"
  description = "Security group for EC2 Instance Connect scenario target instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.user_public_ip.response_body)}/32"]
    description = "Allow SSH from user public IP only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "pl-prod-eic-to-admin-sg"
    Environment = var.environment
    Scenario    = "ec2-instance-connect-sendsshpublickey"
    Purpose     = "security-group"
  }
}

# EC2 instance with admin role attached
resource "aws_instance" "target" {
  provider             = aws.prod
  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_admin.name
  subnet_id            = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids = [
    aws_security_group.target_instance.id
  ]

  # Public IP needed for SSH access via EC2 Instance Connect
  associate_public_ip_address = true

  # IMDSv2 enabled (more secure but still vulnerable to credential extraction)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Enforce IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  tags = {
    Name        = "pl-prod-eic-to-admin-target-instance"
    Environment = var.environment
    Scenario    = "ec2-instance-connect-sendsshpublickey"
    Purpose     = "target-instance"
  }
}
