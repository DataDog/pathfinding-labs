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
# bedrock-agentcore:CreateHarness without hard-coding account IDs.
output "target_role_arn" {
  description = "ARN of the admin target role passed to the Harness at creation time"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the admin target role"
  value       = aws_iam_role.target_role.name
}

# Bedrock model ID — surfaced so demo scripts can reference the configured
# model without hard-coding a default.
output "bedrock_model_id" {
  description = "Bedrock foundation model ID supplied at CreateHarness time"
  value       = var.bedrock_model_id
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
  value       = "User (pl-prod-bedrock-005-to-admin-starting-user) → iam:PassRole + bedrock-agentcore:CreateHarness/CreateAgentRuntime/CreateAgentRuntimeEndpoint/CreateWorkloadIdentity/GetAgentRuntime → new Harness with admin execution role (pl-prod-bedrock-005-to-admin-target-role) → bedrock-agentcore:InvokeAgentRuntimeCommand → curl MMDS 169.254.169.254 → extract admin credentials → ssm:GetParameter /pathfinding-labs/flags/bedrock-005-to-admin → CTF flag"
}
