variable "dev_account_id" {
  description = "AWS Account ID for the dev account"
  type        = string
}

variable "prod_account_id" {
  description = "AWS Account ID for the prod account"
  type        = string
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resource names"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "flag_value" {
  description = "CTF flag value stored in the SSM parameter that the attacker must retrieve to complete the scenario. Populated by plabs from flags.default.yaml (or a vendor override). Defaults to flag{MISSING} so the module is deployable in isolation."
  type        = string
  default     = "flag{MISSING}"
}
