variable "account_id" {
  description = "AWS Account ID for the prod environment"
  type        = string
}

variable "attacker_account_id" {
  description = "Attacker account ID (for attacker-side resource naming)"
  type        = string
}

variable "environment" {
  description = "Environment name (prod)"
  type        = string
  default     = "prod"
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resources"
  type        = string
}
