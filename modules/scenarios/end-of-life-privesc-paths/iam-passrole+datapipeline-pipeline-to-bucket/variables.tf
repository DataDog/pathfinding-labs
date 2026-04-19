variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "attacker_account_id" {
  description = "Attacker account ID (for attacker-controlled exfil bucket naming)"
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
