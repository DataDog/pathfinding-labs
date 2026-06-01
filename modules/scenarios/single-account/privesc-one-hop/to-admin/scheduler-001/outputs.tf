# Starting user outputs — required by plabs TUI to surface credentials and
# determine whether the scenario is "deployed and ready to learn".
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

# Scheduler admin role outputs
output "scheduler_role_arn" {
  description = "ARN of the scheduler admin role (passed via iam:PassRole and assumed by EventBridge Scheduler)"
  value       = aws_iam_role.scheduler_role.arn
}

output "scheduler_role_name" {
  description = "Name of the scheduler admin role"
  value       = aws_iam_role.scheduler_role.name
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
  description = "Description of the attack path"
  value       = "User (pl-prod-scheduler-001-to-admin-starting-user) → iam:PassRole + scheduler:CreateSchedule → creates one-shot EventBridge Scheduler schedule with universal target arn:aws:scheduler:::aws-sdk:iam:attachUserPolicy → schedule fires as pl-prod-scheduler-001-to-admin-scheduler-role (AdministratorAccess) → iam:AttachUserPolicy attaches AdministratorAccess to starting user → ssm:GetParameter /pathfinding-labs/flags/scheduler-001-to-admin → CTF flag"
}
