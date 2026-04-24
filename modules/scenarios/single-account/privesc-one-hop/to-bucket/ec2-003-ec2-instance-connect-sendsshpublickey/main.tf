terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# EC2 Instance Connect SendSSHPublicKey to-bucket privilege escalation scenario
#
# This scenario demonstrates how an attacker with ec2-instance-connect:SendSSHPublicKey
# can SSH into an EC2 instance and extract S3 bucket role credentials via IMDS

# Resource naming convention: pl-prod-ec2-003-to-bucket-{resource-type}
# ec2-003 = Pathfinding.cloud ID for EC2 Instance Connect

# =============================================================================
# DATA SOURCES
# =============================================================================

# Get the latest Amazon Linux 2023 AMI (EC2 Instance Connect compatible)
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

# Get the current user's public IP address
data "http" "user_public_ip" {
  url = "https://checkip.amazonaws.com"
}

# =============================================================================
# S3 BUCKET (TARGET)
# =============================================================================

# Target S3 bucket with sensitive data
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-sensitive-data-ec2-003-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-sensitive-data-ec2-003-bucket"
    Environment = var.environment
    Scenario    = "ec2-instance-connect-sendsshpublickey"
    Purpose     = "target-bucket"
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "target_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "target_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access (this is a private bucket)
resource "aws_s3_bucket_public_access_block" "target_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload a test file to demonstrate access
resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "CONGRATULATIONS! You have successfully extracted IMDS credentials from the EC2 instance and accessed the sensitive S3 bucket. This demonstrates the risk of ec2-instance-connect:SendSSHPublicKey on instances with privileged roles."
}

# CTF flag stored as an S3 object in the target bucket. The attacker retrieves this after
# successfully SSHing into the EC2 instance, extracting IMDS credentials, and using those
# credentials to read from the target bucket. Readable by any principal with s3:GetObject on this bucket.
resource "aws_s3_object" "flag" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "flag.txt"
  content  = var.flag_value
}

# =============================================================================
# IAM ROLE FOR EC2 (WITH S3 BUCKET ACCESS)
# =============================================================================

# EC2 bucket role - trust policy for EC2 service
resource "aws_iam_role" "ec2_bucket_role" {
  provider = aws.prod
  name     = "pl-prod-ec2-003-to-bucket-ec2-bucket-role"

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
    Name        = "pl-prod-ec2-003-to-bucket-ec2-bucket-role"
    Environment = var.environment
    Scenario    = "ec2-instance-connect-sendsshpublickey"
    Purpose     = "ec2-bucket-access"
  }
}

# Grant full S3 access to the target bucket
resource "aws_iam_role_policy" "ec2_bucket_access" {
  provider = aws.prod
  name     = "pl-prod-ec2-003-to-bucket-s3-policy"
  role     = aws_iam_role.ec2_bucket_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.target_bucket.arn,
          "${aws_s3_bucket.target_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Create instance profile for the role
resource "aws_iam_instance_profile" "ec2_bucket_profile" {
  provider = aws.prod
  name     = "pl-prod-ec2-003-to-bucket-instance-profile"
  role     = aws_iam_role.ec2_bucket_role.name

  tags = {
    Name        = "pl-prod-ec2-003-to-bucket-instance-profile"
    Environment = var.environment
    Scenario    = "ec2-instance-connect-sendsshpublickey"
    Purpose     = "ec2-instance-profile"
  }
}

# =============================================================================
# SECURITY GROUP
# =============================================================================

# Security group allowing SSH access
resource "aws_security_group" "eic_sg" {
  provider    = aws.prod
  name        = "pl-prod-ec2-003-to-bucket-sg"
  description = "Allow SSH access for EC2 Instance Connect"

  ingress {
    description = "SSH from user public IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.user_public_ip.response_body)}/32"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "pl-prod-ec2-003-to-bucket-sg"
    Environment = var.environment
    Scenario    = "ec2-instance-connect-sendsshpublickey"
    Purpose     = "security-group"
  }
}

# =============================================================================
# EC2 INSTANCE
# =============================================================================

# EC2 instance with Instance Connect and S3 bucket access
resource "aws_instance" "target" {
  provider               = aws.prod
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  iam_instance_profile   = aws_iam_instance_profile.ec2_bucket_profile.name
  vpc_security_group_ids = [aws_security_group.eic_sg.id]

  # Public IP required for SSH access
  associate_public_ip_address = true

  # Enable IMDSv2 (best practice)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  tags = {
    Name        = "pl-prod-ec2-003-to-bucket-target-instance"
    Environment = var.environment
    Scenario    = "ec2-instance-connect-sendsshpublickey"
    Purpose     = "target-instance"
  }
}

# =============================================================================
# STARTING USER (SCENARIO-SPECIFIC)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-ec2-003-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-ec2-003-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "ec2-instance-connect-sendsshpublickey"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy for the starting user
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-ec2-003-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  # Ensure the instance exists before creating the policy
  depends_on = [aws_instance.target]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationSendSSHPublicKey"
        Effect = "Allow"
        Action = [
          "ec2-instance-connect:SendSSHPublicKey"
        ]
        Resource = aws_instance.target.arn
      }
    ]
  })
}
