# Scenario-specific starting user outputs (REQUIRED)
output "starting_user_name" {
  description = "Name of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.arn
}

output "starting_user_access_key_id" {
  description = "Access key ID for the starting user"
  value       = aws_iam_access_key.starting_user.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the starting user"
  value       = aws_iam_access_key.starting_user.secret
  sensitive   = true
}

# EC2 instance outputs
output "ec2_instance_id" {
  description = "ID of the target EC2 instance with admin role"
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

# EC2 admin role outputs
output "ec2_admin_role_name" {
  description = "Name of the EC2 instance's admin role"
  value       = aws_iam_role.ec2_admin.name
}

output "ec2_admin_role_arn" {
  description = "ARN of the EC2 instance's admin role"
  value       = aws_iam_role.ec2_admin.arn
}

# Security group allowed IP
output "allowed_ssh_ip" {
  description = "The public IP address allowed to SSH into the EC2 instance"
  value       = "${chomp(data.http.user_public_ip.response_body)}/32"
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-eic-to-admin-starting-user) → ec2-instance-connect:SendSSHPublicKey → EC2 Instance (${aws_instance.target.id}) → IMDS Credential Extraction → Admin Access"
}
