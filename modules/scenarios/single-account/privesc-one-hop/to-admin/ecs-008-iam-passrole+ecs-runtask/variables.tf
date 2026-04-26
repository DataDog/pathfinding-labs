variable "account_id" {
  description = "AWS Account ID for the prod environment"
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

variable "flag_value" {
  description = "CTF flag value stored in SSM Parameter Store, retrieved after successful privilege escalation"
  type        = string
  default     = "flag{MISSING}"
}
