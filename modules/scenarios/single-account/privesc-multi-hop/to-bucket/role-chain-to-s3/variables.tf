variable "prod_account_id" {
  description = "Production account ID"
  type        = string
}

variable "operations_account_id" {
  description = "Operations account ID"
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
  description = "CTF flag value placed in the target S3 bucket as flag.txt"
  type        = string
  default     = "flag{MISSING}"
}
