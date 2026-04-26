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

variable "vpc_id" {
  description = "VPC ID to deploy resources into"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID to deploy resources into"
  type        = string
}

variable "flag_value" {
  description = "CTF flag value to store in SSM Parameter Store"
  type        = string
  default     = "flag{MISSING}"
}
