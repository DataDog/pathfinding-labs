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

output "privesc_role_arn" {
  description = "ARN of the privilege escalation role"
  value       = aws_iam_role.privesc_role.arn
}

output "privesc_role_name" {
  description = "Name of the privilege escalation role"
  value       = aws_iam_role.privesc_role.name
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
  value       = data.aws_subnets.default.ids[0]
}

output "ami_id" {
  description = "ID of the Amazon Linux 2023 AMI"
  value       = data.aws_ami.amazon_linux_2023.id
}

output "policy_arn" {
  description = "ARN of the privilege escalation policy"
  value       = aws_iam_policy.privesc_policy.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-one-hop-prec-starting-user) → AssumeRole → Role (pl-prod-one-hop-prec-role) → PassRole + RunInstances → EC2 Instance (backdoors admin role) → AssumeRole → Admin Role (pl-prod-one-hop-prec-admin-role) → Administrator Access"
}
