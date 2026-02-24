# =============================================================================
# STARTING USER OUTPUTS (Required for demo scripts)
# =============================================================================

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

# =============================================================================
# LAMBDA FUNCTION OUTPUTS
# =============================================================================

output "lambda_function_name" {
  description = "Name of the target Lambda function"
  value       = aws_lambda_function.target_function.function_name
}

output "lambda_function_arn" {
  description = "ARN of the target Lambda function"
  value       = aws_lambda_function.target_function.arn
}

# =============================================================================
# LAMBDA ROLE OUTPUTS
# =============================================================================

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role (has iam:CreateAccessKey permission)"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

# =============================================================================
# ADMIN USER OUTPUTS (Target of the attack)
# =============================================================================

output "admin_user_arn" {
  description = "ARN of the admin user (target of privilege escalation)"
  value       = aws_iam_user.admin_user.arn
}

output "admin_user_name" {
  description = "Name of the admin user"
  value       = aws_iam_user.admin_user.name
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of the multi-hop attack path"
  value       = "User (pl-prod-lambda-004-to-iam-002-starting-user) -> UpdateFunctionCode + InvokeFunction -> Lambda Function (pl-prod-lambda-004-to-iam-002-target-function) -> Exfiltrate Lambda Role credentials (pl-prod-lambda-004-to-iam-002-lambda-role) -> CreateAccessKey -> Admin User (pl-prod-lambda-004-to-iam-002-admin-user) -> Admin Access"
}
