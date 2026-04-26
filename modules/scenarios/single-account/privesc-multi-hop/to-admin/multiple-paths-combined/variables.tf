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
  description = "Environment name (prod, dev, operations)"
  type        = string
  default     = "prod"
}

variable "flag_value" {
  description = "CTF flag value placed in the SSM parameter that the attacker must retrieve to complete the scenario"
  type        = string
  default     = "flag{MISSING}"
}
