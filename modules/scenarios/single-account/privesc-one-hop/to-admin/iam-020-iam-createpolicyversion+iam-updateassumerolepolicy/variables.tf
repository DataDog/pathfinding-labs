variable "account_id" {
  description = "AWS Account ID"
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
  description = "CTF flag value stored in the scenario's flag resource. Populated by plabs from flags.default.yaml (or a vendor override). Defaults to flag{MISSING} so the module is deployable in isolation."
  type        = string
  default     = "flag{MISSING}"
}
