variable "account_id" {
  description = "AWS Account ID for the prod account"
  type        = string
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resources"
  type        = string
}

variable "environment" {
  description = "Environment name (prod)"
  type        = string
  default     = "prod"
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
  description = "CTF flag value placed in the target S3 bucket as flag.txt"
  type        = string
  default     = "flag{MISSING}"
}
