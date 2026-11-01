output "plain_reader_name" {
  value = aws_iam_user.plain_reader.name
}
output "plain_reader_arn" {
  value = aws_iam_user.plain_reader.arn
}
output "plain_reader_access_key_id" {
  value     = aws_iam_access_key.plain_reader.id
  sensitive = true
}
output "plain_reader_secret_access_key" {
  value     = aws_iam_access_key.plain_reader.secret
  sensitive = true
}

output "explicit_deny_reader_name" {
  value = aws_iam_user.explicit_deny_reader.name
}
output "explicit_deny_reader_arn" {
  value = aws_iam_user.explicit_deny_reader.arn
}
output "explicit_deny_reader_access_key_id" {
  value     = aws_iam_access_key.explicit_deny_reader.id
  sensitive = true
}
output "explicit_deny_reader_secret_access_key" {
  value     = aws_iam_access_key.explicit_deny_reader.secret
  sensitive = true
}

output "boundary_excludes_s3_name" {
  value = aws_iam_user.boundary_excludes_s3.name
}
output "boundary_excludes_s3_arn" {
  value = aws_iam_user.boundary_excludes_s3.arn
}
output "boundary_excludes_s3_access_key_id" {
  value     = aws_iam_access_key.boundary_excludes_s3.id
  sensitive = true
}
output "boundary_excludes_s3_secret_access_key" {
  value     = aws_iam_access_key.boundary_excludes_s3.secret
  sensitive = true
}

output "bucket_name" {
  value = aws_s3_bucket.target.id
}
output "bucket_arn" {
  value = aws_s3_bucket.target.arn
}
output "attack_path" {
  value = "plain-reader reads the bucket; explicit-deny-reader (inline Deny) and boundary-excludes-s3 (EC2-only permissions boundary) look like readers but have no effective S3 access"
}
