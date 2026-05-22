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

# Target role outputs
output "target_role_arn" {
  description = "ARN of the target role (passed to Lambda via iam:PassRole)"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target role"
  value       = aws_iam_role.target_role.name
}

# Target S3 bucket outputs
output "target_bucket_name" {
  description = "Name of the target S3 bucket containing the CTF flag"
  value       = aws_s3_bucket.target_bucket.id
}

output "target_bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.arn
}

# DynamoDB table outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB trigger table (streams enabled)"
  value       = aws_dynamodb_table.trigger_table.id
}

output "dynamodb_stream_arn" {
  description = "ARN of the DynamoDB stream on the trigger table"
  value       = aws_dynamodb_table.trigger_table.stream_arn
}

output "exfil_table_name" {
  description = "Name of the DynamoDB exfil table where Lambda writes the flag (no stream)"
  value       = aws_dynamodb_table.exfil_table.id
}

# CTF flag outputs
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
  value       = "User (pl-prod-lambda-002-to-bucket-starting-user) → PassRole + CreateFunction → Lambda with S3-access role → CreateEventSourceMapping (DynamoDB stream trigger) → PutItem triggers Lambda → Lambda reads flag.txt from S3 → Lambda writes flag to exfil DynamoDB table → GetItem retrieves flag"
}
