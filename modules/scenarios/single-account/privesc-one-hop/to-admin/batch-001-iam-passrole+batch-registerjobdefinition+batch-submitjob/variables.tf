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
  description = "VPC ID for scenario resources"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for scenario resources"
  type        = string
}
