variable "account_id" {
  description = "AWS Account ID for the prod account"
  type        = string
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resources"
  type        = string
}

variable "environment" {
  description = "Environment name (prod)"
  type        = string
  default     = "prod"
}

variable "flag_value" {
  description = "CTF flag value placed in the SSM parameter that the attacker must retrieve to complete the scenario"
  type        = string
  default     = "flag{MISSING}"
}