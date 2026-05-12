# =============================================================================
# STARTING USER OUTPUTS (Required for all scenarios)
# =============================================================================

output "starting_user_name" {
  description = "Name of the starting IAM user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the starting IAM user"
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

# =============================================================================
# ADMIN ROLE + INSTANCE PROFILE OUTPUTS (Privilege Escalation Target)
# =============================================================================

output "admin_role_arn" {
  description = "ARN of the admin role (target)"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role"
  value       = aws_iam_role.admin_role.name
}

output "admin_instance_profile_arn" {
  description = "ARN of the admin instance profile used by Image Builder"
  value       = aws_iam_instance_profile.admin_profile.arn
}

output "admin_instance_profile_name" {
  description = "Name of the admin instance profile"
  value       = aws_iam_instance_profile.admin_profile.name
}

# =============================================================================
# NETWORK OUTPUTS (VPC for Image Builder)
# =============================================================================

output "default_subnet_id" {
  description = "Subnet ID used for infrastructure configuration"
  value       = var.subnet_id
}

output "build_security_group_id" {
  description = "Security group ID for the Image Builder build instance"
  value       = aws_security_group.build_instance.id
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "starting_user (${aws_iam_user.starting_user.name}) -> imagebuilder:CreateComponent (malicious shell commands) -> imagebuilder:CreateImageRecipe + imagebuilder:CreateInfrastructureConfiguration (iam:PassRole ${aws_iam_instance_profile.admin_profile.name}) -> imagebuilder:CreateImage (launches EC2 build instance) -> component commands execute with admin credentials via IMDS -> attaches AdministratorAccess to starting user -> admin access"
}
