variable "dev_account_id" {
  description = "Dev AWS Account ID"
  type        = string
}

variable "prod_account_id" {
  description = "Prod AWS Account ID"
  type        = string
}

variable "environment" {
  description = "Environment name (cross-account)"
  type        = string
  default     = "cross-account"
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resources"
  type        = string
}
