variable "dev_account_id" {
  description = "The AWS account ID for the dev environment"
  type        = string
}

variable "prod_account_id" {
  description = "The AWS account ID for the prod environment"
  type        = string
}

variable "operations_account_id" {
  description = "The AWS account ID for the operations environment"
  type        = string
}

variable "resource_suffix" {
  description = "Random suffix for globally namespaced resources"
  type        = string
}

variable "flag_value" {
  description = "CTF flag value stored in the SSM parameter that the attacker must retrieve to complete the scenario. Populated by plabs from flags.default.yaml (or a vendor override). Defaults to flag{MISSING} so the module is deployable in isolation."
  type        = string
  default     = "flag{MISSING}"
}
