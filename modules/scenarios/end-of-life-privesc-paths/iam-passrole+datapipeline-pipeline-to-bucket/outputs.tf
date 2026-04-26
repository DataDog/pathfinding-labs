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

# Pipeline role outputs
output "pipeline_role_arn" {
  description = "ARN of the pipeline role"
  value       = aws_iam_role.pipeline_role.arn
}

output "pipeline_role_name" {
  description = "Name of the pipeline role"
  value       = aws_iam_role.pipeline_role.name
}

# Sensitive bucket outputs
output "sensitive_bucket_name" {
  description = "Name of the sensitive data bucket"
  value       = aws_s3_bucket.sensitive_bucket.id
}

output "sensitive_bucket_arn" {
  description = "ARN of the sensitive data bucket"
  value       = aws_s3_bucket.sensitive_bucket.arn
}

# Exfiltration bucket outputs (attacker-controlled — deployed in attacker account)
output "exfil_bucket_name" {
  description = "Name of the attacker-controlled exfiltration bucket"
  value       = aws_s3_bucket.exfil_bucket.id
}

output "exfil_bucket_arn" {
  description = "ARN of the attacker-controlled exfiltration bucket"
  value       = aws_s3_bucket.exfil_bucket.arn
}

# CTF flag outputs
output "flag_s3_key" {
  description = "S3 object key for the CTF flag file in the sensitive bucket"
  value       = aws_s3_object.flag.key
}

output "flag_s3_uri" {
  description = "S3 URI of the CTF flag object"
  value       = "s3://${aws_s3_bucket.sensitive_bucket.id}/${aws_s3_object.flag.key}"
}

# Attack path description
output "attack_path" {
  description = "Description of the attack path"
  value       = "User (pl-prod-datapipeline-001-to-bucket-starting-user) → datapipeline:CreatePipeline with iam:PassRole → EC2 instance running as pipeline role (s3:GetObject on sensitive bucket) → reads sensitive bucket data → writes to attacker-controlled exfil bucket → sensitive data exfiltrated"
}
