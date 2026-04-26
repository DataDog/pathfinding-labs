# Scenario-specific starting user outputs (dev account)
output "starting_user_arn" {
  description = "ARN of the scenario-specific starting user in dev account"
  value       = aws_iam_user.starting_user.arn
}

output "starting_user_name" {
  description = "Name of the scenario-specific starting user in dev account"
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

# Target role outputs (prod account)
output "target_role_arn" {
  description = "ARN of the target admin role in prod account"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target admin role in prod account"
  value       = aws_iam_role.target_role.name
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "dev:User (${aws_iam_user.starting_user.name}) → (AssumeRole) → prod:Role (${aws_iam_role.target_role.name}) → admin access in prod"
}

# CTF flag outputs
output "flag_ssm_parameter_name" {
  description = "SSM Parameter Store name for the CTF flag (requires prod admin access to read)"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM Parameter Store entry for the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}
