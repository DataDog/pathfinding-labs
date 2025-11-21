# Scenario-specific starting user outputs
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

# CloudFormation stack outputs
output "stack_name" {
  description = "Name of the CloudFormation stack"
  value       = aws_cloudformation_stack.vulnerable_stack.name
}

output "stack_role_arn" {
  description = "ARN of the CloudFormation stack service role"
  value       = aws_iam_role.stack_role.arn
}

output "escalated_role_name" {
  description = "Name of the role that will be created via stack update (for demo reference)"
  value       = "pl-prod-cus-to-admin-escalated-role"
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-cus-to-admin-starting-user) → cloudformation:UpdateStack → Stack (pl-prod-cus-to-admin-stack with admin service role) → Creates escalated admin role (pl-prod-cus-to-admin-escalated-role) → sts:AssumeRole → Admin access"
}
