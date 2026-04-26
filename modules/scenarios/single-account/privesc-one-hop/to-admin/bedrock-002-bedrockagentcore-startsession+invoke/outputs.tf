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

# Target role outputs
output "target_role_arn" {
  description = "ARN of the target admin role"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target admin role"
  value       = aws_iam_role.target_role.name
}

# Existing code interpreter outputs
output "existing_interpreter_id" {
  description = "ID of the existing code interpreter with admin role"
  value       = aws_bedrockagentcore_code_interpreter.existing_interpreter.code_interpreter_id
}

output "existing_interpreter_arn" {
  description = "ARN of the existing code interpreter with admin role"
  value       = aws_bedrockagentcore_code_interpreter.existing_interpreter.code_interpreter_arn
}

# CTF flag outputs
output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter containing the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

# Attack path description
output "attack_path" {
  description = "Description of the privilege escalation attack path"
  value       = "User (${aws_iam_user.starting_user.name}) → StartCodeInterpreterSession → Existing code interpreter (${aws_bedrockagentcore_code_interpreter.existing_interpreter.name}) with admin role (${aws_iam_role.target_role.name}) → InvokeCodeInterpreter → Extract credentials from MMDS (169.254.169.254) → Administrative access"
}
