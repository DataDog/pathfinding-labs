output "ops_deployer_role_arn" {
  description = "ARN of the ops deployer role (entry point via GitHub OIDC)"
  value       = aws_iam_role.ops_deployer.arn
}

output "ops_deployer_role_name" {
  description = "Name of the ops deployer role"
  value       = aws_iam_role.ops_deployer.name
}

output "prod_deployer_role_arn" {
  description = "ARN of the prod deployer role (cross-account pivot target)"
  value       = aws_iam_role.prod_deployer.arn
}

output "prod_deployer_role_name" {
  description = "Name of the prod deployer role"
  value       = aws_iam_role.prod_deployer.name
}

output "flag_bucket_name" {
  description = "Name of the flag S3 bucket containing sensitive data"
  value       = aws_s3_bucket.flag_bucket.id
}

output "flag_bucket_arn" {
  description = "ARN of the flag S3 bucket"
  value       = aws_s3_bucket.flag_bucket.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider in the operations account"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "attack_path" {
  description = "Description of the attack path for this scenario"
  value       = "GitHub Actions (${var.github_repo}) → ops:pl-ops-goidc-pivot-deployer-role → prod:pl-prod-goidc-pivot-deployer-role → s3 bucket"
}
