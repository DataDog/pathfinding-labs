output "starting_user_name" {
  value = aws_iam_user.starting_user.name
}
output "starting_user_arn" {
  value = aws_iam_user.starting_user.arn
}
output "starting_user_access_key_id" {
  value     = aws_iam_access_key.starting_user.id
  sensitive = true
}
output "starting_user_secret_access_key" {
  value     = aws_iam_access_key.starting_user.secret
  sensitive = true
}

output "policy_granted_role_name" {
  value = aws_iam_role.policy_granted.name
}
output "policy_granted_role_arn" {
  value = aws_iam_role.policy_granted.arn
}

output "identity_reader_name" {
  value = aws_iam_user.identity_reader.name
}
output "identity_reader_arn" {
  value = aws_iam_user.identity_reader.arn
}
output "identity_reader_access_key_id" {
  value     = aws_iam_access_key.identity_reader.id
  sensitive = true
}
output "identity_reader_secret_access_key" {
  value     = aws_iam_access_key.identity_reader.secret
  sensitive = true
}

output "denied_reader_name" {
  value = aws_iam_user.denied_reader.name
}
output "denied_reader_arn" {
  value = aws_iam_user.denied_reader.arn
}
output "denied_reader_access_key_id" {
  value     = aws_iam_access_key.denied_reader.id
  sensitive = true
}
output "denied_reader_secret_access_key" {
  value     = aws_iam_access_key.denied_reader.secret
  sensitive = true
}

output "denied_admin_name" {
  value = aws_iam_user.denied_admin.name
}
output "denied_admin_arn" {
  value = aws_iam_user.denied_admin.arn
}
output "denied_admin_access_key_id" {
  value     = aws_iam_access_key.denied_admin.id
  sensitive = true
}
output "denied_admin_secret_access_key" {
  value     = aws_iam_access_key.denied_admin.secret
  sensitive = true
}

output "bucket_name" {
  value = aws_s3_bucket.target.id
}
output "bucket_arn" {
  value = aws_s3_bucket.target.arn
}
output "attack_path" {
  value = "starting-user -> (AssumeRole) -> policy-granted-role -> (bucket policy grant) -> bucket; identity-reader reads via identity policy; denied-reader and denied-admin are blocked by an explicit bucket-policy Deny"
}
