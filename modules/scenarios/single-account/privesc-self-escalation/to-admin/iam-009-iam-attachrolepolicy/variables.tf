variable "prod_account_id" {
  description = "The account ID of the production account"
  type        = string
}

variable "dev_account_id" {
  description = "The account ID of the development account"
  type        = string
}

variable "operations_account_id" {
  description = "The account ID of the operations account"
  type        = string
}

variable "resource_suffix" {
  description = "Random suffix for globally namespaced resources to prevent conflicts"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, dev, ops)"
  type        = string
  default     = "prod"
}

variable "flag_value" {
  description = "CTF flag value stored in SSM Parameter Store. Set via plabs flags (loaded from flags.default.yaml or a vendor override file). Defaults to flag{MISSING} so the module is deployable in isolation."
  type        = string
  default     = "flag{MISSING}"
}
