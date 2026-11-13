# =============================================================================
# STARTING USER OUTPUTS (REQUIRED FOR ALL SCENARIOS)
# =============================================================================

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

# =============================================================================
# EC2 INSTANCE OUTPUTS
# =============================================================================

output "ec2_instance_id" {
  description = "ID of the target EC2 instance"
  value       = aws_instance.target.id
}

output "ec2_instance_arn" {
  description = "ARN of the target EC2 instance"
  value       = aws_instance.target.arn
}

output "ec2_instance_public_ip" {
  description = "Public IP address of the target EC2 instance"
  value       = aws_instance.target.public_ip
}

# =============================================================================
# IAM ROLE OUTPUTS
# =============================================================================

output "ec2_bucket_role_name" {
  description = "Name of the EC2 bucket role"
  value       = aws_iam_role.ec2_bucket_role.name
}

output "ec2_bucket_role_arn" {
  description = "ARN of the EC2 bucket role"
  value       = aws_iam_role.ec2_bucket_role.arn
}

# =============================================================================
# S3 BUCKET OUTPUTS
# =============================================================================

output "target_bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.id
}

output "target_bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.arn
}

# =============================================================================
# SECURITY GROUP CONFIGURATION
# =============================================================================

output "allowed_ssh_ip" {
  description = "The public IP address allowed to SSH into the EC2 instance"
  value       = "${chomp(data.http.user_public_ip.response_body)}/32"
}

# =============================================================================
# ATTACK PATH SUMMARY
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (${aws_iam_user.starting_user.name}) → (ec2-instance-connect:SendSSHPublicKey) → EC2 instance (${aws_instance.target.id}) → (IMDS credential extraction) → S3 bucket access (${aws_s3_bucket.target_bucket.id})"
}

# =============================================================================
# CTF FLAG OUTPUTS
# =============================================================================

output "flag_s3_key" {
  description = "S3 object key for the CTF flag file in the target bucket"
  value       = aws_s3_object.flag.key
}

output "flag_s3_uri" {
  description = "S3 URI of the CTF flag object"
  value       = "s3://${aws_s3_bucket.target_bucket.id}/${aws_s3_object.flag.key}"
}
