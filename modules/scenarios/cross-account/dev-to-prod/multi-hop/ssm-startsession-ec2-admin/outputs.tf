output "starting_user_name" {
  description = "Name of the scenario-specific starting user in the dev account"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the scenario-specific starting user in the dev account"
  value       = aws_iam_user.starting_user.arn
}

output "starting_user_access_key_id" {
  description = "Access key ID for the scenario-specific starting user"
  value       = aws_iam_access_key.starting_user.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for the scenario-specific starting user"
  value       = aws_iam_access_key.starting_user.secret
  sensitive   = true
}

output "prod_pivot_role_arn" {
  description = "ARN of the prod SSM pivot role assumed cross-account from dev"
  value       = aws_iam_role.ssm_pivot_role.arn
}

output "prod_pivot_role_name" {
  description = "Name of the prod SSM pivot role"
  value       = aws_iam_role.ssm_pivot_role.name
}

output "ec2_instance_id" {
  description = "Instance ID of the target EC2 instance with the admin instance profile"
  value       = aws_instance.target_ec2.id
}

output "ec2_instance_arn" {
  description = "ARN of the target EC2 instance"
  value       = aws_instance.target_ec2.arn
}

output "ec2_admin_role_name" {
  description = "Name of the admin IAM role attached to the EC2 instance profile"
  value       = aws_iam_role.ec2_admin_role.name
}

output "ec2_admin_role_arn" {
  description = "ARN of the admin IAM role attached to the EC2 instance profile"
  value       = aws_iam_role.ec2_admin_role.arn
}

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

output "attack_path" {
  description = "Description of the attack path"
  value       = "pl-dev-ssm-ec2-starting-user (dev) → sts:AssumeRole → pl-prod-ssm-ec2-pivot-role (prod) → ssm:SendCommand → EC2 instance → IMDS → pl-prod-ssm-ec2-admin-role (admin) → ssm:GetParameter → CTF flag"
}
