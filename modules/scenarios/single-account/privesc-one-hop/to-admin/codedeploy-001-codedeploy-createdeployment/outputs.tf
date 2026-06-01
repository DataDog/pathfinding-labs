# ─── Starting user (required for all scenarios) ───────────────────────────────

output "starting_user_name" {
  description = "Name of the scenario-specific starting user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the scenario-specific starting user"
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

# ─── EC2 admin role ───────────────────────────────────────────────────────────

output "ec2_role_arn" {
  description = "ARN of the EC2 admin instance role (AdministratorAccess) that the lifecycle hook executes as"
  value       = aws_iam_role.ec2_role.arn
}

output "ec2_role_name" {
  description = "Name of the EC2 admin instance role"
  value       = aws_iam_role.ec2_role.name
}

# ─── CodeDeploy resources ─────────────────────────────────────────────────────

output "app_name" {
  description = "Name of the CodeDeploy application"
  value       = aws_codedeploy_app.app.name
}

output "deployment_group_name" {
  description = "Name of the CodeDeploy deployment group"
  value       = aws_codedeploy_deployment_group.dg.deployment_group_name
}

# ─── Attacker revision bucket ─────────────────────────────────────────────────

output "attacker_bucket" {
  description = "Name of the attacker-controlled S3 bucket hosting the malicious revision ZIP"
  value       = aws_s3_bucket.attacker_revision.id
}

output "revision_key" {
  description = "S3 object key of the malicious revision ZIP in the attacker bucket"
  value       = aws_s3_object.revision.key
}

# ─── CTF flag ─────────────────────────────────────────────────────────────────

output "flag_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.name
}

output "flag_ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CTF flag"
  value       = aws_ssm_parameter.flag.arn
}

# ─── Attack path description ──────────────────────────────────────────────────

output "attack_path" {
  description = "Human-readable description of the attack path"
  value       = "User (pl-prod-codedeploy-001-to-admin-starting-user) → codedeploy:CreateDeployment with malicious appspec.yml revision staged in attacker S3 → CodeDeploy agent on target EC2 runs BeforeInstall hook as admin instance profile (pl-prod-codedeploy-001-to-admin-ec2-role / AdministratorAccess) → hook calls iam:AttachUserPolicy AdministratorAccess on starting user → ssm:GetParameter /pathfinding-labs/flags/codedeploy-001-to-admin → CTF flag"
}
