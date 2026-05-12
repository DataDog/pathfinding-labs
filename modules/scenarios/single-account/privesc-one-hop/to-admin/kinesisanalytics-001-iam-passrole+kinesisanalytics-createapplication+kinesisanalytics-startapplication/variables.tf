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

variable "attacker_account_id" {
  description = "AWS Account ID for the attacker account (hosts pre-staged exploit artifacts)"
  type        = string
}
