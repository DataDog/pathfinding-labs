output "privesc_role_arn" {
  description = "ARN of the role with multiple privilege escalation paths"
  value       = aws_iam_role.prod_role_with_multiple_privesc_paths.arn
}

output "privesc_role_name" {
  description = "Name of the role with multiple privilege escalation paths"
  value       = aws_iam_role.prod_role_with_multiple_privesc_paths.name
}

output "ec2_admin_role_arn" {
  description = "ARN of the EC2 admin role"
  value       = aws_iam_role.prod_ec2_admin_role.arn
}

output "lambda_admin_role_arn" {
  description = "ARN of the Lambda admin role"
  value       = aws_iam_role.prod_lambda_admin_role.arn
}

output "cloudformation_admin_role_arn" {
  description = "ARN of the CloudFormation admin role"
  value       = aws_iam_role.prod_cloudformation_admin_role.arn
}
