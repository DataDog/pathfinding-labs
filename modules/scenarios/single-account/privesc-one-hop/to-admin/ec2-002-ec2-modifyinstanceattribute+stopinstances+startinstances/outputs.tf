# Scenario-specific starting user outputs (REQUIRED FOR ALL SCENARIOS)
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

# Target role outputs
output "target_role_arn" {
  description = "ARN of the target admin role attached to the EC2 instance"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target admin role"
  value       = aws_iam_role.target_role.name
}

# Instance profile outputs
output "target_instance_profile_arn" {
  description = "ARN of the instance profile"
  value       = aws_iam_instance_profile.target_profile.arn
}

output "target_instance_profile_name" {
  description = "Name of the instance profile"
  value       = aws_iam_instance_profile.target_profile.name
}

# EC2 instance outputs
output "target_instance_id" {
  description = "ID of the target EC2 instance"
  value       = aws_instance.target_instance.id
}

output "target_instance_public_ip" {
  description = "Public IP address of the target EC2 instance"
  value       = aws_instance.target_instance.public_ip
}

output "target_instance_private_ip" {
  description = "Private IP address of the target EC2 instance"
  value       = aws_instance.target_instance.private_ip
}

output "initial_user_data" {
  description = "The initial benign user data script"
  value       = aws_instance.target_instance.user_data
  sensitive   = true
}

# VPC and networking outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = var.vpc_id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = var.subnet_id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.target_sg.id
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-ec2-002-to-admin-starting-user) → (ec2:StopInstances) → (ec2:ModifyInstanceAttribute with malicious cloud-init payload) → (ec2:StartInstances) → malicious script executes on boot → extract credentials from IMDS at 169.254.169.254 → admin access via pl-prod-ec2-002-to-admin-target-role"
}

# Additional helpful information
output "imds_endpoint" {
  description = "Instance Metadata Service endpoint for credential extraction"
  value       = "http://169.254.169.254/latest/meta-data/iam/security-credentials/${aws_iam_role.target_role.name}"
}

output "imdsv2_token_endpoint" {
  description = "IMDSv2 token endpoint (required for this instance)"
  value       = "http://169.254.169.254/latest/api/token"
}
