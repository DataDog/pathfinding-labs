# =============================================================================
# STARTING PRINCIPAL OUTPUTS (EC2 Instance Role)
# =============================================================================

output "starting_principal_arn" {
  description = "ARN of the starting principal (EC2 instance role)"
  value       = aws_iam_role.container_instance.arn
}

output "starting_principal_name" {
  description = "Name of the starting principal (EC2 instance role)"
  value       = aws_iam_role.container_instance.name
}

# =============================================================================
# TARGET ROLE OUTPUTS
# =============================================================================

output "target_role_arn" {
  description = "ARN of the target admin role"
  value       = aws_iam_role.target_role.arn
}

output "target_role_name" {
  description = "Name of the target admin role"
  value       = aws_iam_role.target_role.name
}

# =============================================================================
# ECS CLUSTER OUTPUTS
# =============================================================================

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.cluster.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.cluster.arn
}

# =============================================================================
# TASK DEFINITION OUTPUTS
# =============================================================================

output "existing_task_definition_arn" {
  description = "ARN of the pre-existing task definition (exploited via StartTask --overrides)"
  value       = aws_ecs_task_definition.existing_task.arn
}

# =============================================================================
# EC2 CONTAINER INSTANCE OUTPUTS
# =============================================================================

output "container_instance_id" {
  description = "ID of the EC2 container instance (NOT registered to cluster at deploy time)"
  value       = aws_instance.container_instance.id
}

# =============================================================================
# ATTACK PATH DESCRIPTION
# =============================================================================

output "attack_path" {
  description = "Description of the attack path"
  value       = "instance_role (${aws_iam_role.container_instance.name}) on EC2 (${aws_instance.container_instance.id}) -> (attacker has RCE) -> ecs:RegisterContainerInstance (direct API call with IMDS identity docs) -> reconfigure ECS agent -> ecs:StartTask with --overrides (iam:PassRole admin role + command override) -> ECS task attaches AdministratorAccess to instance role -> admin access"
}

# =============================================================================
# CTF FLAG OUTPUT
# =============================================================================

output "flag_ssm_parameter_name" {
  description = "SSM Parameter Store name containing the CTF flag"
  value       = aws_ssm_parameter.flag.name
}
