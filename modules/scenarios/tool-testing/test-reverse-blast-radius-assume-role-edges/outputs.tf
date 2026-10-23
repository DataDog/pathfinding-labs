output "are_both_name" {
  value = aws_iam_user.are_both.name
}
output "are_both_arn" {
  value = aws_iam_user.are_both.arn
}
output "are_both_access_key_id" {
  value     = aws_iam_access_key.are_both.id
  sensitive = true
}
output "are_both_secret_access_key" {
  value     = aws_iam_access_key.are_both.secret
  sensitive = true
}

output "are_identity_only_name" {
  value = aws_iam_user.are_identity_only.name
}
output "are_identity_only_arn" {
  value = aws_iam_user.are_identity_only.arn
}
output "are_identity_only_access_key_id" {
  value     = aws_iam_access_key.are_identity_only.id
  sensitive = true
}
output "are_identity_only_secret_access_key" {
  value     = aws_iam_access_key.are_identity_only.secret
  sensitive = true
}

output "are_trust_only_name" {
  value = aws_iam_user.are_trust_only.name
}
output "are_trust_only_arn" {
  value = aws_iam_user.are_trust_only.arn
}
output "are_trust_only_access_key_id" {
  value     = aws_iam_access_key.are_trust_only.id
  sensitive = true
}
output "are_trust_only_secret_access_key" {
  value     = aws_iam_access_key.are_trust_only.secret
  sensitive = true
}

output "are_root_with_identity_name" {
  value = aws_iam_user.are_root_with_identity.name
}
output "are_root_with_identity_arn" {
  value = aws_iam_user.are_root_with_identity.arn
}
output "are_root_with_identity_access_key_id" {
  value     = aws_iam_access_key.are_root_with_identity.id
  sensitive = true
}
output "are_root_with_identity_secret_access_key" {
  value     = aws_iam_access_key.are_root_with_identity.secret
  sensitive = true
}

output "are_root_no_identity_name" {
  value = aws_iam_user.are_root_no_identity.name
}
output "are_root_no_identity_arn" {
  value = aws_iam_user.are_root_no_identity.arn
}
output "are_root_no_identity_access_key_id" {
  value     = aws_iam_access_key.are_root_no_identity.id
  sensitive = true
}
output "are_root_no_identity_secret_access_key" {
  value     = aws_iam_access_key.are_root_no_identity.secret
  sensitive = true
}

output "target_role_name" {
  value = aws_iam_role.target.name
}
output "target_role_arn" {
  value = aws_iam_role.target.arn
}
output "target_role_root_name" {
  value = aws_iam_role.target_root.name
}
output "target_role_root_arn" {
  value = aws_iam_role.target_root.arn
}
output "bucket_name" {
  value = aws_s3_bucket.target.id
}
output "bucket_arn" {
  value = aws_s3_bucket.target.arn
}
output "attack_path" {
  value = "A same-account AssumeRole needs identity permission AND trust; only are-both and are-root-with-identity satisfy both, so only they reach the bucket via the target roles"
}
