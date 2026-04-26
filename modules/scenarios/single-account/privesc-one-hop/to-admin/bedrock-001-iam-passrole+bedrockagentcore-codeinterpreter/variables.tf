variable "account_id" {
  description = "AWS Account ID where resources will be created"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, dev, operations)"
  type        = string
  default     = "prod"
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resource names"
  type        = string
}

variable "flag_value" {
  description = "CTF flag value stored in SSM Parameter Store for this scenario"
  type        = string
  default     = "flag{MISSING}"
}
