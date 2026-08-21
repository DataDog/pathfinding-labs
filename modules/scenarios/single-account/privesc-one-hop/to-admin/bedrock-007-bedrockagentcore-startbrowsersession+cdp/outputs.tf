# Scenario-specific starting user outputs (required for all scenarios)
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

# Target role outputs
output "target_role_arn" {
  description = "ARN of the victim's admin execution role attached to the Custom Browser"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the victim's admin execution role"
  value       = aws_iam_role.target_role.name
}

# Browser ID SSM parameter — the demo script reads this to discover the browser to attack
output "target_browser_ssm_param" {
  description = "SSM parameter name storing the victim Custom Browser ID"
  value       = data.aws_ssm_parameter.victim_browser_id.name
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
  value       = "User (pl-prod-bedrock-007-to-admin-starting-user) → bedrock-agentcore:StartBrowserSession + ConnectBrowserAutomationStream on existing Custom Browser (pl_prod_bedrock_007_to_admin_victim_browser) with admin execution role → CDP/Playwright context.route hook rewrites MMDS token request → read execution role credentials at 169.254.169.254 → admin access (pl-prod-bedrock-007-to-admin-target-role) → ssm:GetParameter → CTF flag"
}
