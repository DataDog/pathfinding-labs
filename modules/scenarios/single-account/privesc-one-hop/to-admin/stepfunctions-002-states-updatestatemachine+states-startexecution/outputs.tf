# =============================================================================
# STARTING USER OUTPUTS (required by plabs TUI for credential display)
# =============================================================================

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

# =============================================================================
# STATE MACHINE OUTPUTS
# =============================================================================

output "state_machine_arn" {
  description = "ARN of the pre-existing state machine the attacker rewrites"
  value       = aws_sfn_state_machine.statemachine.arn
}

output "state_machine_name" {
  description = "Name of the pre-existing state machine the attacker rewrites"
  value       = aws_sfn_state_machine.statemachine.name
}

output "statemachine_role_arn" {
  description = "ARN of the admin execution role already attached to the state machine"
  value       = aws_iam_role.statemachine_role.arn
}

# =============================================================================
# CTF FLAG OUTPUTS
# =============================================================================

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

# =============================================================================
# ATTACK PATH OUTPUT
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-stepfunctions-002-to-admin-starting-user) → states:UpdateStateMachine (replaces benign ASL with malicious definition) → states:StartExecution (state machine runs as pre-existing admin role) → iam:AttachUserPolicy AdministratorAccess on starting user → ssm:GetParameter /pathfinding-labs/flags/stepfunctions-002-to-admin → CTF flag"
}
