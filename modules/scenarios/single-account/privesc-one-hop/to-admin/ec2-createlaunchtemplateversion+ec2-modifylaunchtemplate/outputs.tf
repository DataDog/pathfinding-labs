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

# Low-privilege role outputs
output "lowpriv_role_arn" {
  description = "ARN of the low-privilege role (original template role)"
  value       = aws_iam_role.lowpriv_role.arn
}

output "lowpriv_role_name" {
  description = "Name of the low-privilege role"
  value       = aws_iam_role.lowpriv_role.name
}

output "lowpriv_instance_profile_arn" {
  description = "ARN of the low-privilege instance profile"
  value       = aws_iam_instance_profile.lowpriv_profile.arn
}

# Target admin role outputs
output "target_admin_role_arn" {
  description = "ARN of the target admin role"
  value       = aws_iam_role.target_admin_role.arn
}

output "target_admin_role_name" {
  description = "Name of the target admin role"
  value       = aws_iam_role.target_admin_role.name
}

output "target_admin_instance_profile_arn" {
  description = "ARN of the target admin instance profile"
  value       = aws_iam_instance_profile.target_admin_profile.arn
}

output "target_admin_instance_profile_name" {
  description = "Name of the target admin instance profile"
  value       = aws_iam_instance_profile.target_admin_profile.name
}

# Victim infrastructure outputs
output "victim_launch_template_id" {
  description = "ID of the victim launch template to modify"
  value       = aws_launch_template.victim_template.id
}

output "victim_launch_template_name" {
  description = "Name of the victim launch template"
  value       = aws_launch_template.victim_template.name
}

output "victim_launch_template_latest_version" {
  description = "Latest version number of the victim launch template"
  value       = aws_launch_template.victim_template.latest_version
}

output "victim_asg_name" {
  description = "Name of the victim Auto Scaling Group"
  value       = aws_autoscaling_group.victim_asg.name
}

output "victim_security_group_id" {
  description = "ID of the security group for victim instances"
  value       = aws_security_group.victim_sg.id
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-lt-modify-to-admin-starting-user) → CreateLaunchTemplateVersion (with admin role + malicious user data) → ModifyLaunchTemplate (set default version) → Next instance launch uses admin role → User data grants admin access to starting user"
}
