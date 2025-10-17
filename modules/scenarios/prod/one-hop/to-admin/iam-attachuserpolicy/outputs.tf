output "starting_user_arn" {
  description = "ARN of the starting user with AttachUserPolicy permission"
  value       = aws_iam_user.attachuserpolicy_user.arn
}

output "starting_user_name" {
  description = "Name of the starting user"
  value       = aws_iam_user.attachuserpolicy_user.name
}

output "starting_user_access_key_id" {
  description = "Access key ID for the starting user"
  value       = aws_iam_access_key.attachuserpolicy_user_key.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the starting user"
  value       = aws_iam_access_key.attachuserpolicy_user_key.secret
  sensitive   = true
}

output "attack_path_info" {
  description = "Description of the attack path"
  value       = "User (pl-attachuserpolicy-user) → AttachUserPolicy (AdministratorAccess) → Admin Access"
}

output "next_steps" {
  description = "Instructions for running the demo"
  value       = "Run ./demo_attack.sh to see the privilege escalation in action. The user will attach the AdministratorAccess managed policy to itself."
}
