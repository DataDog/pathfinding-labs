terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# EC2 ModifyInstanceAttribute + StopInstances + StartInstances privilege escalation scenario
#
# This scenario demonstrates how a principal with ec2:ModifyInstanceAttribute, ec2:StopInstances,
# and ec2:StartInstances can inject malicious code into an EC2 instance's userData to extract
# credentials from the attached IAM role via IMDS (Instance Metadata Service).
#
# Attack Path:
# starting_user → (ec2:StopInstances) → (ec2:ModifyInstanceAttribute with malicious cloud-init payload)
# → (ec2:StartInstances) → malicious script executes on boot → extract credentials from IMDS
# at 169.254.169.254 → admin access via attached role

# Resource naming convention: pl-prod-ec2-002-{resource-type}

# Data source to get the latest Amazon Linux 2023 AMI
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

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ec2-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-ec2-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "ec2-modifyinstanceattribute+stopinstances+startinstances"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user (EC2 modify permissions)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-ec2-002-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationEC2Modify"
        Effect = "Allow"
        Action = [
          "ec2:ModifyInstanceAttribute",
          "ec2:StopInstances",
          "ec2:StartInstances"
        ]
        Resource = "arn:aws:ec2:*:*:instance/*"
      },
      {
        Sid    = "RequiredForExploitationEC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceAttribute"
        ]
        Resource = "*"
      }
    ]
  })
}

# Target role with admin access (attached to EC2 instance)
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-ec2-002-to-admin-target-role"

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
    Name        = "pl-prod-ec2-002-to-admin-target-role"
    Environment = var.environment
    Scenario    = "ec2-modifyinstanceattribute+stopinstances+startinstances"
    Purpose     = "target-role"
  }
}

# Attach AdministratorAccess to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Instance profile for the target role
resource "aws_iam_instance_profile" "target_profile" {
  provider = aws.prod
  name     = "pl-prod-ec2-002-to-admin-target-profile"
  role     = aws_iam_role.target_role.name

  tags = {
    Name        = "pl-prod-ec2-002-to-admin-target-profile"
    Environment = var.environment
    Scenario    = "ec2-modifyinstanceattribute+stopinstances+startinstances"
    Purpose     = "instance-profile"
  }
}

# Security group for the EC2 instance (restrictive - no inbound)
resource "aws_security_group" "target_sg" {
  provider    = aws.prod
  name        = "pl-prod-ec2-002-to-admin-sg"
  description = "Security group for EC2 ModifyInstanceAttribute scenario"
  vpc_id      = var.vpc_id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "pl-prod-ec2-002-to-admin-sg"
    Environment = var.environment
    Scenario    = "ec2-modifyinstanceattribute+stopinstances+startinstances"
    Purpose     = "target-sg"
  }
}

# EC2 instance with benign initial user data
resource "aws_instance" "target_instance" {
  provider                    = aws.prod
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  iam_instance_profile        = aws_iam_instance_profile.target_profile.name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.target_sg.id]
  associate_public_ip_address = true

  # Enable IMDSv2 (required)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Require IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  # Benign initial user data
  user_data = <<-EOF
              #!/bin/bash
              echo "Initial boot complete at $(date)" > /var/log/startup.log
              echo "Instance initialized successfully" >> /var/log/startup.log
              EOF

  # Enable detailed monitoring for better CloudWatch metrics
  monitoring = true

  tags = {
    Name        = "pl-prod-ec2-002-to-admin-target-instance"
    Environment = var.environment
    Scenario    = "ec2-modifyinstanceattribute+stopinstances+startinstances"
    Purpose     = "target-instance"
  }

  # Prevent accidental termination
  lifecycle {
    ignore_changes = [user_data]
  }
}

# CTF flag stored in SSM Parameter Store. The attacker retrieves this after reaching
# administrator-equivalent permissions in the account. The flag lives in the victim
# (prod) account and is readable by any principal with ssm:GetParameter on the
# parameter ARN — in practice this means any admin-equivalent principal, since
# AdministratorAccess grants the required permission implicitly.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/ec2-002-to-admin"
  description = "CTF flag for the ec2-002 to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-ec2-002-to-admin-flag"
    Environment = var.environment
    Scenario    = "ec2-modifyinstanceattribute+stopinstances+startinstances"
    Purpose     = "ctf-flag"
  }
}
