# EC2 instance outputs (the misconfiguration)
output "ec2_instance_id" {
  description = "ID of the EC2 instance with privileged role attached"
  value       = aws_instance.target.id
}

output "ec2_instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.target.arn
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

output "instance_profile_name" {
  description = "Name of the instance profile"
  value       = aws_iam_instance_profile.ec2_admin.name
}

output "instance_profile_arn" {
  description = "ARN of the instance profile"
  value       = aws_iam_instance_profile.ec2_admin.arn
}

# Demo user outputs (for demonstrating the risk)
output "demo_user_name" {
  description = "Name of the demo user"
  value       = aws_iam_user.demo_user.name
}

output "demo_user_arn" {
  description = "ARN of the demo user"
  value       = aws_iam_user.demo_user.arn
}

output "demo_user_access_key_id" {
  description = "Access key ID for the demo user"
  value       = aws_iam_access_key.demo_user.id
  sensitive   = true
}

output "demo_user_secret_access_key" {
  description = "Secret access key for the demo user"
  value       = aws_iam_access_key.demo_user.secret
  sensitive   = true
}

# CSPM detection information
output "cspm_check" {
  description = "The CSPM check this scenario validates"
  value       = "aws-ec2-instance-ec2-instance-should-not-have-a-highly-privileged-iam-role-attached-to-it"
}

output "misconfiguration_summary" {
  description = "Description of the misconfiguration"
  value       = "EC2 instance ${aws_instance.target.id} has highly privileged role ${aws_iam_role.ec2_admin.name} (AdministratorAccess) attached via instance profile ${aws_iam_instance_profile.ec2_admin.name}"
}
