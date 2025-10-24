variable "prod_account_id" {
  description = "Production account ID"
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
