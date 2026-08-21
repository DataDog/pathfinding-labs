# Scenario-specific starting user outputs (REQUIRED FOR ALL SCENARIOS)
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
  description = "ARN of the target admin role (victim's execution role attached to the AgentCore Runtime)"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target admin role"
  value       = aws_iam_role.target_role.name
}

# AgentCore Runtime outputs
output "target_runtime_arn" {
  description = "ARN of the victim's AgentCore Runtime (pre-provisioned with the admin execution role)"
  value       = data.aws_ssm_parameter.runtime_arn.value
}

output "target_runtime_name" {
  description = "Name of the victim's AgentCore Runtime"
  value       = local.runtime_name
}

# ECR outputs
output "ecr_repository_url" {
  description = "URL of the victim ECR repository hosting the runtime container image"
  value       = aws_ecr_repository.runtime_image.repository_url
}

output "ecr_image_uri" {
  description = "Full ECR image URI for the AgentCore Runtime container"
  value       = local.ecr_image_uri
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
  description = "Description of the privilege escalation attack path"
  value       = "User (${aws_iam_user.starting_user.name}) → bedrock-agentcore:InvokeAgentRuntimeCommand → existing Runtime (${local.runtime_name}) with admin execution role (${aws_iam_role.target_role.name}) → extract MMDS credentials at 169.254.169.254 → admin access → ssm:GetParameter → CTF flag"
}
