terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# SSM StartSession privilege escalation scenario (to-bucket variant)
#
# This scenario demonstrates how a user with ssm:StartSession permission can remotely
# access an EC2 instance that has S3 bucket access, extract the instance's temporary
# credentials from the metadata endpoint (IMDS), and gain access to sensitive S3 data.

# Resource naming convention: pl-prod-ssm-001-to-bucket-{resource-type}

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
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get default VPC for simplicity
# Get default subnets
# ==============================================================================
# TARGET S3 BUCKET
# ==============================================================================

# Target S3 bucket with sensitive data
resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-sensitive-data-ssm-001-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-sensitive-data-ssm-001-bucket"
    Environment = var.environment
    Scenario    = "ssm-startsession"
    Purpose     = "target-bucket"
  }
}

# Enable versioning on the target bucket
resource "aws_s3_bucket_versioning" "target_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable default encryption on the target bucket
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
  content  = "This is sensitive data that should only be accessible to authorized principals. If you can read this, you have successfully extracted EC2 instance credentials via SSM StartSession."
}

resource "aws_s3_object" "flag" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "flag.txt"
  content  = var.flag_value
}

# ==============================================================================
# SCENARIO-SPECIFIC STARTING USER
# ==============================================================================

resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-ssm-001-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-ssm-001-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "ssm-startsession"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Policy granting SSM StartSession permissions to the starting user
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-ssm-001-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  # Ensure the EC2 instance is created before the policy references it
  depends_on = [aws_instance.target]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationStartSession"
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
        Sid    = "RequiredForExploitationTerminateSession"
        Effect = "Allow"
        Action = [
          "ssm:TerminateSession"
        ]
        Resource = "arn:aws:ssm:*:*:session/*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ssm:DescribeInstanceInformation",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# EC2 BUCKET ROLE (TARGET)
# ==============================================================================

# Role with S3 bucket access that will be attached to the EC2 instance
resource "aws_iam_role" "ec2_bucket_role" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-ssm-001-to-bucket-ec2-role"

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
    Name        = "pl-prod-ssm-001-to-bucket-ec2-role"
    Environment = var.environment
    Scenario    = "ssm-startsession"
    Purpose     = "ec2-bucket-role"
  }
}

# Attach SSM managed instance core policy (required for SSM agent to work)
resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  provider   = aws.prod
  role       = aws_iam_role.ec2_bucket_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Inline policy granting full access to the target S3 bucket
resource "aws_iam_role_policy" "ec2_bucket_access" {
  provider = aws.prod
  name     = "pl-prod-ssm-001-to-bucket-s3-access-policy"
  role     = aws_iam_role.ec2_bucket_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketFullAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          aws_s3_bucket.target_bucket.arn,
          "${aws_s3_bucket.target_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Instance profile to link the role to EC2
resource "aws_iam_instance_profile" "ec2_bucket" {
  provider = aws.prod
  name     = "pl-prod-ssm-001-to-bucket-instance-profile"
  role     = aws_iam_role.ec2_bucket_role.name

  tags = {
    Name        = "pl-prod-ssm-001-to-bucket-instance-profile"
    Environment = var.environment
    Scenario    = "ssm-startsession"
    Purpose     = "instance-profile"
  }
}

# ==============================================================================
# EC2 TARGET INSTANCE
# ==============================================================================

# Security group allowing outbound traffic (needed for SSM to work)
resource "aws_security_group" "target_instance" {
  provider    = aws.prod
  name        = "pl-prod-ssm-001-to-bucket-sg"
  description = "Security group for SSM StartSession scenario target instance"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic for SSM connectivity"
  }

  tags = {
    Name        = "pl-prod-ssm-001-to-bucket-sg"
    Environment = var.environment
    Scenario    = "ssm-startsession"
    Purpose     = "security-group"
  }
}

# EC2 instance with S3 bucket access role attached
resource "aws_instance" "target" {
  provider             = aws.prod
  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = "t3.nano"
  iam_instance_profile = aws_iam_instance_profile.ec2_bucket.name
  subnet_id            = var.subnet_id
  vpc_security_group_ids = [
    aws_security_group.target_instance.id
  ]

  # Public IP needed for SSM connectivity (unless VPC endpoints are configured)
  associate_public_ip_address = true

  tags = {
    Name        = "pl-prod-ssm-001-to-bucket-target-instance"
    Environment = var.environment
    Scenario    = "ssm-startsession"
    Purpose     = "target-instance"
  }
}
