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

# CloudFormation stack outputs
output "stack_name" {
  description = "Name of the target CloudFormation stack"
  value       = aws_cloudformation_stack.target_stack.name
}

output "stack_id" {
  description = "ID of the target CloudFormation stack"
  value       = aws_cloudformation_stack.target_stack.id
}

output "stack_role_arn" {
  description = "ARN of the CloudFormation stack service role (has admin access)"
  value       = aws_iam_role.stack_role.arn
}

output "stack_role_name" {
  description = "Name of the CloudFormation stack service role"
  value       = aws_iam_role.stack_role.name
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-cloudformation-005-to-admin-starting-user) → cloudformation:CreateChangeSet + ExecuteChangeSet on stack (pl-prod-cloudformation-005-to-admin-target-stack) → stack updates using admin service role (pl-prod-cloudformation-005-to-admin-stack-role) → creates escalated-role with admin access → admin privileges"
}
