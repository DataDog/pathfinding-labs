variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "attacker_account_id" {
  description = "Attacker account ID (for attacker-side resource naming)"
  type        = string
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
  description = "CTF flag value stored in SSM Parameter Store. Set via plabs flags (loaded from flags.default.yaml or a vendor override file). Defaults to flag{MISSING} so the module is deployable in isolation."
  type        = string
  default     = "flag{MISSING}"
}
