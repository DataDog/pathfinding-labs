variable "account_id" {
  description = "The AWS account ID where resources will be created"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, dev, ops)"
  type        = string
  default     = "prod"
}

variable "resource_suffix" {
  description = "Random suffix for globally namespaced resources to prevent conflicts"
  type        = string
}

variable "flag_value" {
  description = "CTF flag value to store in the target S3 bucket"
  type        = string
  default     = "flag{MISSING}"
}

