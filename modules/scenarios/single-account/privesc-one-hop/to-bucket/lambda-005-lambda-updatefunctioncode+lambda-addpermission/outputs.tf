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

# Lambda execution role outputs
output "lambda_exec_role_arn" {
  description = "ARN of the Lambda execution role with S3 read access"
  value       = aws_iam_role.lambda_exec_role.arn
}

output "lambda_exec_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_exec_role.name
}

# Aliases for consistency with root outputs.tf
output "target_role_arn" {
  description = "ARN of the target role (alias for lambda_exec_role_arn)"
  value       = aws_iam_role.lambda_exec_role.arn
}

output "target_role_name" {
  description = "Name of the target role (alias for lambda_exec_role_name)"
  value       = aws_iam_role.lambda_exec_role.name
}

# Lambda function outputs
output "target_lambda_function_name" {
  description = "Name of the target Lambda function"
  value       = aws_lambda_function.target_lambda.function_name
}

output "target_lambda_function_arn" {
  description = "ARN of the target Lambda function"
  value       = aws_lambda_function.target_lambda.arn
}

# Target S3 bucket outputs
output "target_bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.id
}

output "target_bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.arn
}

# CTF flag outputs (to-bucket: flag is an S3 object)
output "flag_s3_key" {
  description = "S3 object key for the CTF flag inside the target bucket"
  value       = aws_s3_object.flag.key
}

output "flag_s3_uri" {
  description = "Full s3:// URI for the CTF flag object"
  value       = "s3://${aws_s3_bucket.target_bucket.id}/${aws_s3_object.flag.key}"
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-lambda-005-to-bucket-starting-user) → lambda:UpdateFunctionCode (inject S3-reading payload) → lambda:AddPermission (grant self invoke) → lambda:InvokeFunction → Lambda executes as lambda-exec-role → s3:GetObject flag.txt → CTF flag"
}
