output "bucket_reader_name" {
  value = aws_iam_user.bucket_reader.name
}
output "bucket_reader_arn" {
  value = aws_iam_user.bucket_reader.arn
}
output "bucket_reader_access_key_id" {
  value     = aws_iam_access_key.bucket_reader.id
  sensitive = true
}
output "bucket_reader_secret_access_key" {
  value     = aws_iam_access_key.bucket_reader.secret
  sensitive = true
}

output "cak_user_name" {
  value = aws_iam_user.cak_user.name
}
output "cak_user_arn" {
  value = aws_iam_user.cak_user.arn
}
output "cak_user_access_key_id" {
  value     = aws_iam_access_key.cak_user.id
  sensitive = true
}
output "cak_user_secret_access_key" {
  value     = aws_iam_access_key.cak_user.secret
  sensitive = true
}

output "attach_self_user_name" {
  value = aws_iam_user.attach_self_user.name
}
output "attach_self_user_arn" {
  value = aws_iam_user.attach_self_user.arn
}
output "attach_self_user_access_key_id" {
  value     = aws_iam_access_key.attach_self_user.id
  sensitive = true
}
output "attach_self_user_secret_access_key" {
  value     = aws_iam_access_key.attach_self_user.secret
  sensitive = true
}

output "bucket_name" {
  value = aws_s3_bucket.target.id
}
output "bucket_arn" {
  value = aws_s3_bucket.target.arn
}
output "attack_path" {
  value = "bucket-reader reads the bucket directly; cak-user escalates via iam:CreateAccessKey on bucket-reader; attach-self-user escalates via iam:AttachUserPolicy on itself to gain admin"
}
