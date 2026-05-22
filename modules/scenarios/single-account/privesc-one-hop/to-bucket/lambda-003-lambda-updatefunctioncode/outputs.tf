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

output "target_role_arn" {
  description = "ARN of the Lambda execution role with S3 read access (target role)"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the Lambda execution role with S3 read access (target role)"
  value       = aws_iam_role.target_role.name
}

output "target_lambda_function_name" {
  description = "Name of the pre-existing target Lambda function"
  value       = aws_lambda_function.target_function.function_name
}

output "target_lambda_function_arn" {
  description = "ARN of the pre-existing target Lambda function"
  value       = aws_lambda_function.target_function.arn
}

output "target_bucket_name" {
  description = "Name of the target S3 bucket containing sensitive data and the CTF flag"
  value       = aws_s3_bucket.target_bucket.id
}

output "target_bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.arn
}

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
  value       = "User (pl-prod-lambda-003-to-bucket-starting-user) → lambda:UpdateFunctionCode → existing Lambda (pl-prod-lambda-003-to-bucket-target-lambda, TARGET_BUCKET pre-set by Terraform) → lambda:InvokeFunction → Lambda reads flag.txt from S3 using target role (pl-prod-lambda-003-to-bucket-target-role) → CTF flag in response body"
}
