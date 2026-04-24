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

output "admin_role_arn" {
  description = "ARN of the admin role (target)"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = aws_iam_role.admin_role.name
}

output "instance_profile_arn" {
  description = "ARN of the admin instance profile"
  value       = aws_iam_instance_profile.admin_instance_profile.arn
}

output "instance_profile_name" {
  description = "Name of the admin instance profile"
  value       = aws_iam_instance_profile.admin_instance_profile.name
}

output "security_group_id" {
  description = "ID of the security group for EC2 instances"
  value       = aws_security_group.ec2_sg.id
}

output "default_subnet_id" {
  description = "ID of the default subnet for EC2 instance launch"
  value       = var.subnet_id
}

output "ami_id" {
  description = "ID of the Amazon Linux 2023 AMI"
  value       = data.aws_ami.amazon_linux_2023.id
}

# CTF flag outputs
output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "starting_user → (PassRole + RequestSpotInstances) → Spot instance with admin profile → (AttachUserPolicy AdministratorAccess) → admin access → ssm:GetParameter → CTF flag"
}
