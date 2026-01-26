output "starting_user_arn" {
  description = "ARN of the starting user with AttachUserPolicy permission"
  value       = aws_iam_user.starting_user.arn
}

output "starting_user_name" {
  description = "Name of the starting user"
  value       = aws_iam_user.starting_user.name
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

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-iam-008-to-admin-starting-user) → AttachUserPolicy (AdministratorAccess) → Admin Access"
}

output "next_steps" {
  description = "Instructions for running the demo"
  value       = "Run ./demo_attack.sh to see the privilege escalation in action. The user will attach the AdministratorAccess managed policy to itself."
}
