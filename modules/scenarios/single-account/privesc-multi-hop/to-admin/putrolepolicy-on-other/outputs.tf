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

output "role_a_arn" {
  description = "ARN of RoleA (non-admin role with PutRolePolicy permission)"
  value       = aws_iam_role.prod_role_a.arn
}

output "role_a_name" {
  description = "Name of RoleA"
  value       = aws_iam_role.prod_role_a.name
}

output "role_b_arn" {
  description = "ARN of RoleB (admin role that trusts RoleA)"
  value       = aws_iam_role.prod_role_b.arn
}

output "role_b_name" {
  description = "Name of RoleB"
  value       = aws_iam_role.prod_role_b.name
}

output "admin_bucket_name" {
  description = "Name of the admin demo S3 bucket"
  value       = aws_s3_bucket.prod_admin_demo_bucket.bucket
}

output "admin_bucket_arn" {
  description = "ARN of the admin demo S3 bucket"
  value       = aws_s3_bucket.prod_admin_demo_bucket.arn
}

output "role_a_policy_arn" {
  description = "ARN of the policy that allows RoleA to modify RoleB's policies"
  value       = aws_iam_policy.prod_role_a_policy.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-prpo-to-admin-starting-user) → AssumeRole → RoleA (pl-prod-role-a-non-admin) → PutRolePolicy → RoleB (pl-prod-role-b-admin) → AssumeRole → Admin Access"
}
