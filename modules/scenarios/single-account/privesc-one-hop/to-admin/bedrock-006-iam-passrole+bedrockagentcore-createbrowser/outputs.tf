# Starting user outputs — required by every scenario so the plabs TUI can
# display "deployed and ready to learn" and demo scripts can retrieve creds.
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

# Target role outputs — used by demo scripts to supply the role ARN to
# bedrock-agentcore:CreateBrowser without hard-coding account IDs.
output "target_role_arn" {
  description = "ARN of the admin target role passed to the Custom Browser at creation time"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the admin target role"
  value       = aws_iam_role.target_role.name
}

# CTF flag resource identifiers
output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

# Human-readable attack path for the plabs TUI details pane.
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-bedrock-006-to-admin-starting-user) → iam:PassRole + bedrock-agentcore:CreateBrowser → new Custom Browser with admin execution role (pl-prod-bedrock-006-to-admin-target-role) → bedrock-agentcore:StartBrowserSession + ConnectBrowserAutomationStream → CDP/Playwright context.route hook rewrites MMDS token request → read execution role credentials at 169.254.169.254 → ssm:GetParameter /pathfinding-labs/flags/bedrock-006-to-admin → CTF flag"
}
