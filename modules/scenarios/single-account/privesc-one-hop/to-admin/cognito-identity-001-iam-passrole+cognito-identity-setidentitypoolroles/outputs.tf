# Starting user outputs — required by the plabs TUI to mark the scenario as
# "deployed and ready to learn" and by demo scripts to obtain credentials.
output "starting_user_name" {
  description = "Name of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.arn
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

# Admin role (escalation target)
output "admin_role_arn" {
  description = "ARN of the admin role that gets bound to the Cognito pool's unauthenticated slot"
  value       = aws_iam_role.admin_role.arn
}

output "admin_role_name" {
  description = "Name of the admin role (escalation target)"
  value       = aws_iam_role.admin_role.name
}

# Cognito Identity Pool
output "identity_pool_id" {
  description = "ID of the Cognito Identity Pool (format: region:uuid)"
  value       = aws_cognito_identity_pool.pool.id
}

# CTF flag resource
output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

# Human-readable attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-cognito-identity-001-to-admin-starting-user) → iam:PassRole + cognito-identity:SetIdentityPoolRoles → binds admin role to pool unauthenticated slot → public caller (GetId + GetOpenIdToken + sts:AssumeRoleWithWebIdentity) → admin role credentials → ssm:GetParameter /pathfinding-labs/flags/cognito-identity-001-to-admin → CTF flag"
}
