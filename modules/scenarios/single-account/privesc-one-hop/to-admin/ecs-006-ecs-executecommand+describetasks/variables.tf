variable "account_id" {
  description = "AWS Account ID for the prod environment"
  type        = string
}

variable "environment" {
  description = "Environment name (prod)"
  type        = string
  default     = "prod"
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to deploy resources into"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID to deploy resources into"
  type        = string
}

variable "flag_value" {
  description = "CTF flag value stored in SSM Parameter Store. Set via plabs flags (loaded from flags.default.yaml or a vendor override file). Defaults to flag{MISSING} so the module is deployable in isolation."
  type        = string
  default     = "flag{MISSING}"
}
