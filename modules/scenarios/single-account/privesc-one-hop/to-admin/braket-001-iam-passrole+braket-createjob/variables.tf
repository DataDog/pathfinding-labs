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

variable "attacker_account_id" {
  description = "Attacker account ID (for attacker-side resource naming)"
  type        = string
}

variable "flag_value" {
  description = "CTF flag value stored in the scenario's flag resource. Populated by plabs from flags.default.yaml (or a vendor override). Defaults to flag{MISSING} so the module is deployable in isolation."
  type        = string
  default     = "flag{MISSING}"
}
