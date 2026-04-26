variable "account_id" {
  description = "The AWS account ID where resources will be created"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, dev, ops)"
  type        = string
  default     = "prod"
}

variable "resource_suffix" {
  description = "Random suffix for globally namespaced resources to prevent conflicts"
  type        = string
}

variable "flag_value" {
  description = "CTF flag value placed in the SSM parameter that the attacker must retrieve to complete the scenario"
  type        = string
  default     = "flag{MISSING}"
}
