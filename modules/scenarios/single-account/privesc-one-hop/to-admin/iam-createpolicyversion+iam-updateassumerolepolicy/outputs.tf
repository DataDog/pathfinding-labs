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
  description = "Access key ID for the starting user"
  value       = aws_iam_access_key.starting_user.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the starting user"
  value       = aws_iam_access_key.starting_user.secret
  sensitive   = true
}

# Target policy outputs
output "target_policy_arn" {
  description = "ARN of the customer-managed policy that can be escalated"
  value       = aws_iam_policy.target_policy.arn
}

output "target_policy_name" {
  description = "Name of the customer-managed policy"
  value       = aws_iam_policy.target_policy.name
}

# Target admin role outputs
output "target_role_arn" {
  description = "ARN of the target role whose policy and trust will be modified"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target role"
  value       = aws_iam_role.target_role.name
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-cpvuar-to-admin-starting-user) → (iam:CreatePolicyVersion) → escalate pl-prod-cpvuar-to-admin-target-policy permissions → (iam:UpdateAssumeRolePolicy) → modify pl-prod-cpvuar-to-admin-target-role trust policy → (sts:AssumeRole) → Administrator"
}
