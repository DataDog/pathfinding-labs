output "privesc_user_name" {
  description = "Name of the starting privilege escalation user"
  value       = aws_iam_user.privesc_user.name
}

output "privesc_user_access_key_id" {
  description = "Access key ID for the privesc user"
  value       = aws_iam_access_key.privesc_user_key.id
  sensitive   = true
}

output "privesc_user_secret_access_key" {
  description = "Secret access key for the privesc user"
  value       = aws_iam_access_key.privesc_user_key.secret
  sensitive   = true
}

output "bucket_access_user_name" {
  description = "Name of the user with S3 bucket access"
  value       = aws_iam_user.bucket_access_user.name
}

output "target_bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.id
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "User (privesc-user) → CreateAccessKey (bucket-access-user) → Use new credentials → S3 Bucket Access"
}

# CTF flag outputs
output "flag_s3_key" {
  description = "S3 object key for the CTF flag file in the target bucket"
  value       = aws_s3_object.flag.key
}

output "flag_s3_uri" {
  description = "S3 URI of the CTF flag object"
  value       = "s3://${aws_s3_bucket.target_bucket.id}/${aws_s3_object.flag.key}"
}

