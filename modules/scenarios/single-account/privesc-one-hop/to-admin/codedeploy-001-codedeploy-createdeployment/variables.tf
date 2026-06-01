variable "account_id" {
  description = "AWS Account ID for the prod/victim account"
  type        = string
}

variable "attacker_account_id" {
  description = "AWS Account ID for the attacker account (used for bucket name). Defaults to account_id when no separate attacker account is configured."
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (prod, dev, operations)"
  type        = string
  default     = "prod"
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resources"
  type        = string
}

variable "flag_value" {
  description = "CTF flag value stored in the scenario's flag resource. Populated by plabs from flags.default.yaml (or a vendor override). Defaults to flag{MISSING} so the module is deployable in isolation."
  type        = string
  default     = "flag{MISSING}"
}

variable "vpc_id" {
  description = "VPC ID to deploy resources into"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID to deploy the EC2 instance into"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the CodeDeploy agent install URL and hook script AWS CLI calls"
  type        = string
  default     = "us-east-1"
}
