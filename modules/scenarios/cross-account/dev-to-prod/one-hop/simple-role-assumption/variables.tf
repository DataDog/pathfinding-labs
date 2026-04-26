variable "dev_account_id" {
  description = "AWS Dev Account ID"
  type        = string
}

variable "prod_account_id" {
  description = "AWS Prod Account ID"
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

variable "flag_value" {
  description = "CTF flag value stored in SSM Parameter Store after gaining admin access in prod"
  type        = string
  default     = "flag{MISSING}"
}
