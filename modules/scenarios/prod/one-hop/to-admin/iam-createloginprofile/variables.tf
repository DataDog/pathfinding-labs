variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resources"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, dev, operations)"
  type        = string
  default     = "prod"
}